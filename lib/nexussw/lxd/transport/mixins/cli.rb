require 'nexussw/lxd/transport/mixins/local'
require 'nexussw/lxd/transport/mixins/helpers/users'
require 'nexussw/lxd/transport/mixins/helpers/folder_txfr'
require 'tempfile'
require 'shellwords'

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

          include Helpers::FolderTxfr
          include Helpers::UsersMixin

          def execute(command, options = {}, &block)
            command = runas_command(command, options) unless options[:subcommand]
            command = command.shelljoin if command.is_a?(Array)
            subcommand = options[:subcommand]
            unless subcommand
              subcommand = "exec #{container_name} --"
              # command = ['bash', '-c', command].shelljoin
            end
            command = "lxc #{subcommand} #{command}"

            options = options.reject { |k, _| [:subcommand, :runas].include? k }

            inner_transport.execute command, options, &block
          end

          def read_file(path)
            tfile = Transport.remote_tempname(container_name)
            retval = execute("#{@container_name}#{path} #{tfile}", subcommand: 'file pull', capture: false)
            # return '' if retval.exitstatus == 1
            retval.error!
            return inner_transport.read_file tfile
          ensure
            inner_transport.execute("rm -rf #{tfile}", capture: false) if tfile
          end

          def write_file(path, content, options = {})
            perms = file_perms(options)

            tfile = Transport.remote_tempname(container_name)
            inner_transport.write_file tfile, content
            execute("#{tfile} #{container_name}#{path}", subcommand: "file push#{perms}", capture: false).error!
          ensure
            inner_transport.execute("rm -rf #{tfile}", capture: false) if tfile
          end

          def download_file(path, local_path)
            tfile = Transport.remote_tempname(container_name) if punt
            localname = tfile || local_path
            execute("#{container_name}#{path} #{localname}", subcommand: 'file pull').error!
            inner_transport.download_file tfile, local_path if tfile
          ensure
            inner_transport.execute("rm -rf #{tfile}", capture: false) if tfile
          end

          def upload_file(local_path, path, options = {})
            perms = file_perms(options)

            tfile = Transport.remote_tempname(container_name) if punt
            localname = tfile || local_path
            inner_transport.upload_file local_path, tfile if tfile
            execute("#{localname} #{container_name}#{path}", subcommand: "file push#{perms}").error!
          ensure
            inner_transport.execute("rm -rf #{tfile}", capture: false) if tfile
          end

          def upload_folder(local_path, path, options = {})
            return super unless config[:info] && config[:info]['api_extensions'] && config[:info]['api_extensions'].include?('directory_manipulation')

            execute("-r #{local_path} #{container_name}#{path}", subcommand: 'file push', capture: false).error!
          end

          def download_folder(path, local_path, options = {})
            return super unless config[:info] && config[:info]['api_extensions'] && config[:info]['api_extensions'].include?('directory_manipulation')

            execute("-r #{container_name}#{path} #{local_path}", subcommand: 'file pull', capture: false).error!
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

          def file_perms(options = {})
            perms = ''
            perms += " --uid=#{options[:uid] || uid || 0}"
            perms += " --gid=#{options[:gid] || gid || 0}"
            fmode = options[:file_mode] || file_mode
            perms += " --mode=#{fmode}" if fmode
            perms
          end
        end
      end
    end
  end
end
