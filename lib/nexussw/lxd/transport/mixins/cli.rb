require 'nexussw/lxd/transport/mixins/local'
require 'tempfile'
require 'pp'

module NexusSW
  module LXD
    class Transport
      module Mixins
        module CLI
          def initialize(remote_transport, container_name, config = {})
            @container_name = container_name
            @config = config
            @inner_transport = remote_transport
            @punt = !inner_transport.is_a?(::NexusSW::LXD::Transport::Mixins::Local)
          end
          attr_reader :inner_transport, :punt, :container_name, :config

          def execute(command, options = {})
            mycommand = command.is_a?(Array) ? command.join(' ') : command
            subcommand = options[:subcommand] || "exec #{container_name} --"
            mycommand = "lxc #{subcommand} #{mycommand}"
            options = options.except :subcommand if options.key? :subcommand
            # We would have competing timeout logic depending on who the inner transport is
            # I'll just let rest & local do the timeouts, and if inner is a chef sourced transport, they have timeout logic of their own
            # with_timeout_and_retries(options) do
            inner_transport.execute mycommand, options
          end

          def read_file(path)
            tfile = inner_mktmp
            retval = execute("#{@container_name}#{path} #{tfile}", subcommand: 'file pull', capture: false)
            return '' if retval.exitstatus == 1
            retval.error!
            return inner_transport.read_file tfile
          ensure
            inner_transport.execute("rm -rf #{tfile}", capture: false) if tfile
          end

          def write_file(path, content)
            tfile = inner_mktmp
            inner_transport.write_file tfile, content
            execute("#{tfile} #{container_name}#{path}", subcommand: 'file push', capture: false).error!
          ensure
            inner_transport.execute("rm -rf #{tfile}", capture: false) if tfile
          end

          def download_file(path, local_path)
            tfile = inner_mktmp if punt
            localname = tfile || local_path
            execute("#{container_name}#{path} #{localname}", subcommand: 'file pull', capture: false).error!
            inner_transport.download_file tfile, local_path if tfile
          ensure
            inner_transport.execute("rm -rf #{tfile}", capture: false) if tfile
          end

          def upload_file(local_path, path)
            tfile = inner_mktmp if punt
            localname = tfile || local_path
            inner_transport.upload_file local_path, tfile if tfile
            execute("#{localname} #{container_name}#{path}", subcommand: 'file push', capture: false).error!
          ensure
            inner_transport.execute("rm -rf #{tfile}", capture: false) if tfile
          end

          def add_remote(host_name)
            execute("add #{host_name} --accept-certificate", subcommand: 'remote').error! unless remote? host_name
          end

          def linked_transport(host_name)
            linked = inner_transport.linked_transport(host_name) if inner_transport.is_a?(::NexusSW::LXD::Transport::CLI)
            return linked if linked
            return nil unless remote?(host_name)
            new(driver, inner_transport, "#{host_name}:#{container_name}", config)
          end

          def remote?(host_name)
            result = execute 'list', subcommand: 'remote'
            result.error!
            result.stdout.each_line do |line|
              return true if line.start_with? "| #{host_name} "
            end
            false
          end

          private

          # kludge for windows environment
          def inner_mktmp
            tfile = Tempfile.new(container_name)
            "/tmp/#{File.basename tfile.path}"
          ensure
            tfile.unlink
          end
        end
      end
    end
  end
end
