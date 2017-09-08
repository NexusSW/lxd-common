require 'nexussw/lxd/driver'
require 'tempfile'
require 'yaml'
require 'json'

module NexusSW
  module LXD
    class Driver
      class CLI < Driver
        def initialize(inner_transport, driver_options = {})
          @inner_transport = inner_transport
          @driver_options = driver_options || {}
        end

        attr_reader :inner_transport, :driver_options

        def create_container(container_name, container_options = {})
          cline = "lxc launch #{image_alias(container_options)} #{container_name}"
          profiles = container_options[:profiles] || []
          profiles.each { |p| cline += " -p #{p}" }
          configs = container_options[:config] || {}
          configs.each { |k, v| cline += " -c #{k}=#{v}" }
          inner_transport.execute(cline).error!
          container_name
        end

        def start_container(container_id)
          return if container_status(container_id) == 'running'
          inner_transport.execute("lxc start #{container_id}").error!
          wait_for_status container_id, 'running'
        end

        def stop_container(container_id)
          return if container_status(container_id) == 'stopped'
          inner_transport.execute("lxc stop #{container_id}").error!
          wait_for_status container_id, 'stopped'
        end

        def delete_container(container_id)
          return unless container_exists? container_id
          inner_transport.execute("lxc stop -f #{container_id}").error! unless container_status(container_id) == 'stopped'
          inner_transport.execute("lxc delete #{container_id}").error!
        end

        def container_status(container_id)
          # too heavy for a quick status check - container call results in 3 lxc execs
          # STATUSCODES[container(container_id)[:status_code].to_i]

          res = inner_transport.execute("lxc info #{container_id}")
          res.error!
          info = YAML.load res.stdout
          info['Status'].downcase
        end

        def ensure_profiles(profiles = {})
          profile_list = begin
                            res = inner_transport.execute 'lxc profile list'
                            res.error!
                            res.stdout
                          end
          profiles.each do |name, profile|
            found = false
            profile_list.each_line do |line|
              found = line.start_with? "| #{name} "
              break if found
            end
            next if found
            inner_transport.execute "lxc profile create #{name}"
            tfile = Tempfile.new name
            tfile.close
            begin
              inner_transport.write_file tfile.path, profile.to_hash.to_yaml
              begin
                inner_transport.execute("bash -c 'cat #{tfile.path} | lxc profile edit #{name}'").error!
              ensure
                inner_transport.execute("rm -rf #{tfile.path}").error!
              end
            ensure
              tfile.unlink
            end
          end
        end

        def convert_keys(oldhash, level = 1)
          return {} unless oldhash
          retval = {}
          level -= 1
          oldhash.each do |k, v|
            retval[k.to_sym] = level > 0 ? convert_keys(v, level) : v
          end
          retval
        end

        def container(container_id)
          res = inner_transport.execute("lxc config show #{container_id}")
          res.error!
          config = YAML.load res.stdout
          res = inner_transport.execute("lxc config show #{container_id} --expanded")
          res.error!
          expanded = YAML.load res.stdout
          res = inner_transport.execute("lxc info #{container_id}")
          res.error!
          info = YAML.load res.stdout

          # rearrange to match the REST version
          expanded[:expanded_config] = expanded['config'] || {}
          expanded[:expanded_devices] = expanded['devices'] || {}
          expanded.delete 'config'
          expanded.delete 'devices'
          config = expanded.merge config

          # add a few fields to more closely mimic the REST version
          config[:created_at] = info['Created']
          config[:name] = container_id
          config[:status] = info['Status']
          STATUS_CODES.each do |k, v|
            if config[:status].downcase == v
              config[:status_code] = k
              break
            end
          end
          retval = convert_keys(config)
          retval[:config] = convert_keys(retval[:config])
          retval[:expanded_config] = convert_keys(retval[:expanded_config])
          retval[:devices] = convert_keys(retval[:devices], 2)
          retval[:expanded_devices] = convert_keys(retval[:expanded_devices], 2)
          retval
        end

        private

        def remote_for!(url, protocol = 'lxd')
          raise 'Protocol is required' unless protocol # protect me from accidentally slipping in a nil
          # normalize the url and 'require' protocol to protect against a scenario:
          #   1) user only specifies https://someimageserver.org without specifying the protocol
          #   2) the rest of this function would blindly add that without saying the protocol
          #   3) 'lxc remote add' would add that remote, but defaults to the lxd protocol and appends ':8443' to the saved url
          #   4) the next time this function is called we would not match that same entry due to the ':8443'
          #   5) ultimately resulting in us adding a new remote EVERY time this function is called
          port = url.split(':', 3)[2]
          url += ':8443' unless port || protocol != 'lxd'
          remotes = begin
                      YAML.load(inner_transport.read_file("#{ENV['HOME']}/.config/lxc/config.yml")) || {}
                    rescue
                      {}
                    end
          # make sure these default entries are available to us even if config.yml isn't created yet
          # and i've seen instances where these defaults don't live in the config.yml
          remotes = { 'remotes' => {
            'images' => { 'addr' => 'https://images.linuxcontainers.org' },
            'ubuntu' => { 'addr' => 'https://cloud-images.ubuntu.com/releases' },
            'ubuntu-daily' => { 'addr' => 'https://cloud-images.ubuntu.com/daily' },
          } }.merge remotes
          max = 0
          remotes['remotes'].each do |remote, data|
            return remote.to_s if data['addr'] == url
            num = remote.to_s.split('-', 2)[1] if remote.to_s.start_with? 'images-'
            max = num.to_i if num && num.to_i > max
          end
          remote = "images-#{max + 1}"
          inner_transport.execute("lxc remote add #{remote} #{url} --accept-certificate --protocol=#{protocol}").error!
          remote
        end

        def image(properties, remote = '')
          return nil unless properties && properties.any?
          cline = "lxc image list #{remote} --format=json"
          properties.each { |k, v| cline += " #{k}=#{v}" }
          res = inner_transport.execute cline
          res.error!
          res = JSON.parse(res.stdout)
          return res[0]['fingerprint'] if res.any?
        end

        def image_alias(container_options)
          remote = container_options[:server] ? remote_for!(container_options[:server], container_options[:protocol] || 'lxd') + ':' : ''
          name = container_options[:alias]
          name ||= container_options[:fingerprint]
          name ||= image(container_options[:properties], remote)
          raise 'No image parameters.  One of alias, fingerprint, or properties must be specified (The CLI interface does not support empty containers)' unless name
          "#{remote}#{name}"
        end
      end
    end
  end
end
