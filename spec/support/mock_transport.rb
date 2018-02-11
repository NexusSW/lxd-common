
require 'nexussw/lxd/transport/mixins/helpers/execute'
require 'nexussw/lxd/transport/mixins/helpers/folder_txfr'
require 'spec_helper'
require 'yaml'
require 'shellwords'
require 'pp'

module NexusSW
  module LXD
    class Transport
      class Mock < Transport
        def initialize(config = {})
          @config = config
          init_files_for_container 'mock:'
        end

        attr_reader :config

        @@containers = {} # rubocop:disable Style/ClassVars
        @@files = {} # rubocop:disable Style/ClassVars
        def split_container_name(filename)
          @@containers.each { |k, _| return [k, filename.sub(k, '')] if filename.start_with? k }
          [nil, filename]
        end

        def init_files_for_container(container_name)
          (@@files[container_name] ||= {})['/etc/passwd'] = "root:x:0:0:root:/root:/bin/bash\nubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash\n"
          @@files[container_name]['/run/cloud-init/result.json'] = '{
            "v1": {
             "datasource": "DataSourceNoCloud [seed=/var/lib/cloud/seed/nocloud-net][dsmode=net]",
             "errors": []
            }
           }'
        end

        include Mixins::Helpers::ExecuteMixin
        include Mixins::Helpers::FolderTxfr

        def running_container_state
          {
            'status_code' => 103,
            'network' => {
              'eth0' => {
                'addresses' => [{
                  'address' => '127.0.0.1',
                  'family' => 'inet',
                }],
              },
            },
          }
        end

        def mock
          true
        end

        def new_container(name)
          {
            'status_code' => 103,
            'name' => name,
            'state' => running_container_state,
            'expanded_devices' => {
              'eth0' => {
                'type' => 'nic',
              },
            },
          }
        end

        class StdinStub
          attr_accessor :block

          def write(_cmd)
            @block.call '/' if @block
          end
        end

        def execute_chunked(command, options, &block)
          exitstatus = 0
          if command.is_a?(Array)
            args = command
            command = command.shelljoin
          else
            args = command.shellsplit
          end

          # pp 'top:', command, args
          begin
            case args[0]
            when 'su'
              return execute_chunked(args[3], options, &block)
            when 'bash'
              return execute_chunked(args[2], options, &block)
            when 'lxc'
              case args[1]
              when 'list' then (args[2] ? yield("[#{@@containers[args[2]].to_json}]") : yield(@@containers.to_json))
              # when 'info' then yield @@containers[args[2]].to_yaml
              when 'launch'
                exitstatus = 1 unless args[2].include? 'ubuntu:'
                @@containers[args[3]] = new_container(args[3]) if args[2].include? 'ubuntu:'
              when 'exec'
                if options[:capture] == :interactive
                  stub = StdinStub.new(&block)
                  return Mixins::Helpers::ExecuteMixin::InteractiveResult.new(command, options, stub).tap do |active|
                    stub.block = proc do |stdout|
                      active.send_output stdout
                    end
                    yield active
                    active.exitstatus = 0
                  end
                else
                  subcommand = args[4..-1].shelljoin
                  options[:hostcontainer] = args[2]
                  return execute_chunked(subcommand, options, &block)
                end
              when 'start'
                # @@containers[args[2]]['Status'] = 'Running'
                @@containers[args[2]]['status_code'] = 103
                @@containers[args[2]]['state'] = running_container_state
              when 'stop'
                # @@containers[args[2]]['Status'] = 'Stopped'
                @@containers[args[2]]['status_code'] = 102
                @@containers[args[2]]['state'] = nil
              when 'delete' then @@containers.delete args[2]
              when 'file'
                local = options[:hostcontainer] || 'mock:'
                localfile = ''
                remotehost, remotefile =  case args[2]
                                          when 'push'
                                            idx = 3
                                            idx += 1 if args[idx] == '-r' # rubocop:disable Metrics/BlockNesting
                                            idx += 1 if args[idx].start_with? '--uid=' # rubocop:disable Metrics/BlockNesting
                                            idx += 1 if args[idx].start_with? '--gid=' # rubocop:disable Metrics/BlockNesting
                                            idx += 1 if args[idx].start_with? '--mode=' # rubocop:disable Metrics/BlockNesting
                                            localfile = args[idx]
                                            split_container_name args[idx + 1]
                                          when 'pull'
                                            localfile = args[4]
                                            split_container_name args[3]
                                          end
                case args[2]
                when 'push'
                  init_files_for_container remotehost
                  @@files[remotehost][remotefile] = @@files[local][localfile]
                  @@files[local].each do |f, content|
                    if f.start_with?(localfile + '/') # rubocop:disable Metrics/BlockNesting
                      @@files[remotehost][f.sub(File.dirname(localfile), remotefile)] = content
                    end
                  end
                when 'pull'
                  init_files_for_container local
                  @@files[local][localfile] = @@files[remotehost][remotefile]
                end
              end
            else
              if block_given?
                if command[/find -type d/]
                  yield ".\n./support\n"
                elsif command[/find ! -type d/]
                  yield "./support/shared_contexts.rb\n"
                else
                  yield '/'
                end
              end
            end
          rescue # => e
            exitstatus = 1
          end
          Mixins::Helpers::ExecuteMixin::ExecuteResult.new(command, options, exitstatus)
        end

        def read_file(path)
          @@files['mock:'][path] || ''
        end

        def write_file(path, content)
          @@files['mock:'][path] = content
        end

        def download_file(path, local_path)
          File.open local_path, 'w' do |f|
            f.write @@files['mock:'][path]
          end
        end

        def upload_file(local_path, path)
          raise "File does not exist (#{localpath})" unless File.exist? local_path
          return @@files['mock:'][path] = File.read(local_path) if File.file? local_path
        end
      end
    end
  end
end
