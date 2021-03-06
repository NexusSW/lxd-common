require "nexussw/lxd/driver/mixins/helpers/wait"
require "nexussw/lxd/transport/cli"
require "tempfile"
require "yaml"
require "json"

module NexusSW
  module LXD
    class Driver
      module Mixins
        module CLI
          def initialize(inner_transport, driver_options = {})
            @inner_transport = inner_transport
            @driver_options = driver_options || {}
          end

          attr_reader :inner_transport, :driver_options

          def transport_for(container_name)
            Transport::CLI.new inner_transport, container_name, info: YAML.load(inner_transport.execute("lxc info").error!.stdout)
          end

          def create_container(container_name, container_options = {})
            autostart = (container_options.delete(:autostart) != false)
            if container_exists? container_name
              start_container(container_name) if autostart
              return container_name
            end
            cline = "lxc launch #{image_alias(container_options)} #{container_name}"
            profiles = container_options[:profiles] || []
            profiles.each { |p| cline += " -p #{p}" }
            configs = container_options[:config] || {}
            configs.each { |k, v| cline += " -c #{k}=#{v}" }
            if !autostart || container_options[:devices] # append to the cline to avoid potential lag between create & stop
              cline += " && lxc stop -f #{container_name}"
              cline = ["sh", "-c", cline] # There's no guarantee that inner_transport is running a shell for the && operator
            end
            inner_transport.execute(cline).error!
            if container_options[:devices]
              update_container(container_name, devices: container_options[:devices])
              start_container(container_name) if autostart
            else
              wait_for_status container_name, "running" if autostart
            end
            container_name
          end

          def update_container(container_name, container_options)
            raise NexusSW::LXD::RestAPI::Error::NotFound, "Container (#{container_name}) does not exist" unless container_exists? container_name
            configs = container_options[:config]
            devices = container_options[:devices]
            profiles = container_options[:profiles]
            existing = container(container_name)

            if configs
              configs.each do |k, v|
                if v.nil?
                  next unless existing[:config][k]
                  inner_transport.execute("lxc config unset #{container_name} #{k}").error!
                else
                  next if existing[:config][k] == v
                  inner_transport.execute("lxc config set #{container_name} #{k} #{v}").error!
                end
              end
            end

            if devices
              devices.each do |name, device|
                cmd = "add"
                if device.nil?
                  next unless existing[:devices].include? name
                  inner_transport.execute("lxc config device remove #{container_name} #{name}").error!
                  next
                elsif existing[:devices].include?(name)
                  cmd = "set"
                  if existing[:devices][name][:type] != device[:type]
                    inner_transport.execute("lxc config device remove #{container_name} #{name}").error!
                    cmd = "add"
                  end
                end
                if cmd == "add"
                  cline = "lxc config device add #{container_name} #{name} #{device[:type]}"
                  device.each do |k, v|
                    cline << " #{k}=#{v}"
                  end
                  inner_transport.execute(cline).error!
                else
                  device.each do |k, v|
                    next if k == :type
                    next if v == existing[:devices][name][k]
                    inner_transport.execute("lxc config device set #{container_name} #{name} #{k} #{v}").error!
                  end
                end
              end
            end

            if profiles
              inner_transport.execute("lxc profile assign #{container_name} #{profiles.join(",")}").error! unless profiles == existing[:profiles]
            end

            container container_name
          end

          def start_container(container_id)
            return if container_status(container_id) == "running"
            inner_transport.execute("lxc start #{container_id}").error!
            wait_for_status container_id, "running"
          end

          def stop_container(container_id, options = {})
            options ||= {} # default behavior: no timeout or retries.  These functions are up to the consumer's context and not really 'sane' defaults
            return if container_status(container_id) == "stopped"
            return inner_transport.execute("lxc stop #{container_id} --force", capture: false).error! if options[:force]
            LXD.with_timeout_and_retries(options) do
              return if container_status(container_id) == "stopped"
              timeout = " --timeout=#{options[:retry_interval]}" if options[:retry_interval]
              retval = inner_transport.execute("lxc stop #{container_id}#{timeout || ''}", capture: false)
              begin
                retval.error!
              rescue => e
                return if container_status(container_id) == "stopped"
                # can't distinguish between timeout, or other error.
                # but if the status call is not popping a 404, and we're not stopped, then a retry is worth it
                raise Timeout::Retry.new(e) if timeout # rubocop:disable Style/RaiseArgs
                raise
              end
            end
            wait_for_status container_id, "stopped"
          end

          def delete_container(container_id)
            return unless container_exists? container_id
            inner_transport.execute("lxc delete #{container_id} --force", capture: false).error!
          end

          def container_status(container_id)
            STATUS_CODES[container(container_id)[:status_code].to_i]
          end

          # YAML is not supported until somewhere in the feature branch
          #   the YAML return has :state and :container at the root level
          # the JSON return has no :container (:container is root)
          #   and has :state underneath that
          # (CLI Only) and :state is only available if the container is running
          def container_state(container_id)
            res = inner_transport.execute("lxc list #{container_id} --format=json")
            res.error!
            JSON.parse(res.stdout).each do |c|
              return LXD.symbolize_keys(c["state"]) if c["name"] == container_id
            end
            nil
          end

          def container(container_id)
            res = inner_transport.execute("lxc list #{container_id} --format=json")
            res.error!
            JSON.parse(res.stdout).each do |c|
              return Driver.convert_bools(LXD.symbolize_keys(c.reject { |k, _| k == "state" })) if c["name"] == container_id
            end
            nil
          end

          def container_exists?(container_id)
            return true if container_status(container_id)
            false
          rescue
            false
          end

          include Helpers::WaitMixin

          protected

          def wait_for_status(container_id, newstatus)
            loop do
              status = container_status(container_id)
              return if status == newstatus
              NIO::WebSocket.logger.debug "#{container_id} status = '#{status}'.  Waiting for '#{newstatus}'"
              sleep 0.5
            end
          end

          private

          def remote_for!(url, protocol = "lxd")
            raise "Protocol is required" unless protocol # protect me from accidentally slipping in a nil
            # normalize the url and 'require' protocol to protect against a scenario:
            #   1) user only specifies https://someimageserver.org without specifying the protocol
            #   2) the rest of this function would blindly add that without saying the protocol
            #   3) 'lxc remote add' would add that remote, but defaults to the lxd protocol and appends ':8443' to the saved url
            #   4) the next time this function is called we would not match that same entry due to the ':8443'
            #   5) ultimately resulting in us adding a new remote EVERY time this function is called
            port = url.split(":", 3)[2]
            url += ":8443" unless port || protocol != "lxd"
            remotes = begin
                        YAML.load(inner_transport.read_file("~/.config/lxc/config.yml")) || {}
                      rescue
                        {}
                      end
            # make sure these default entries are available to us even if config.yml isn't created yet
            # and i've seen instances where these defaults don't live in the config.yml
            remotes = { "remotes" => {
              "images" => { "addr" => "https://images.linuxcontainers.org" },
              "ubuntu" => { "addr" => "https://cloud-images.ubuntu.com/releases" },
              "ubuntu-daily" => { "addr" => "https://cloud-images.ubuntu.com/daily" },
            } }.merge remotes
            max = 0
            remotes["remotes"].each do |remote, data|
              return remote.to_s if data["addr"] == url
              num = remote.to_s.split("-", 2)[1] if remote.to_s.start_with? "images-"
              max = num.to_i if num && num.to_i > max
            end
            remote = "images-#{max + 1}"
            inner_transport.execute("lxc remote add #{remote} #{url} --accept-certificate --protocol=#{protocol}").error!
            remote
          end

          def image(properties, remote = "")
            return nil unless properties && properties.any?
            cline = "lxc image list #{remote} --format=json"
            properties.each { |k, v| cline += " #{k}=#{v}" }
            res = inner_transport.execute cline
            res.error!
            res = JSON.parse(res.stdout)
            return res[0]["fingerprint"] if res.any?
          end

          def image_alias(container_options)
            remote = container_options[:server] ? remote_for!(container_options[:server], container_options[:protocol] || "lxd") + ":" : ""
            name = container_options[:alias]
            name ||= container_options[:fingerprint]
            name ||= image(container_options[:properties], remote)
            raise "No image parameters.  One of alias, fingerprint, or properties must be specified (The CLI interface does not support empty containers)" unless name
            "#{remote}#{name}"
          end
        end
      end
    end
  end
end
