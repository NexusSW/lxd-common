require 'nexussw/lxd/transport/mixins/helpers/execute'
require 'nexussw/lxd/transport/mixins/helpers/upload_folder'
require 'spec_helper'
require 'yaml'
require 'pp'

module NexusSW
  module LXD
    class Transport
      class Mock < Transport
        def initialize(config = {})
          @config = config
          @@files['mock:'] ||= {}
        end

        attr_reader :config

        @@containers = {} # rubocop:disable Style/ClassVars
        @@files = {} # rubocop:disable Style/ClassVars
        def split_container_name(filename)
          @@containers.each { |k, _| return [k, filename.sub(k, '')] if filename.start_with? k }
          [nil, filename]
        end

        include Mixins::Helpers::ExecuteMixin
        include Mixins::Helpers::UploadFolder

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

        def execute_chunked(command, options, &block)
          exitstatus = 0
          args = command.is_a?(Array) ? command : command.split(' ')
          begin
            case args[0]
            when 'lxc'
              case args[1]
              when 'list' then yield "[#{@@containers[args[2]].to_json}]"
              # when 'info' then yield @@containers[args[2]].to_yaml
              when 'launch'
                exitstatus = 1 unless args[2].include? 'ubuntu:'
                @@containers[args[3]] = new_container(args[3]) if args[2].include? 'ubuntu:'
              when 'exec'
                yield('/') unless command.include? '-- lxc'
                if command.include? '-- lxc'
                  _, subcommand = command.split(' -- ', 2)
                  return execute_chunked(subcommand, options.merge(hostcontainer: args[2]), &block)
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
                                            idx += 1 if args[3] == '-r' # rubocop:disable Metrics/BlockNesting
                                            localfile = args[idx]
                                            split_container_name args[idx + 1]
                                          when 'pull'
                                            localfile = args[4]
                                            split_container_name args[3]
                                          end
                case args[2]
                when 'push'
                  @@files[remotehost] ||= {}
                  @@files[remotehost][remotefile] = @@files[local][localfile]
                  @@files[local].each do |f, content|
                    if f.start_with?(localfile + '/') # rubocop:disable Metrics/BlockNesting
                      @@files[remotehost][f.sub(File.dirname(localfile), remotefile)] = content
                    end
                  end
                when 'pull'
                  @@files[local] ||= {}
                  @@files[local][localfile] = @@files[remotehost][remotefile]
                end
              end
            end
          rescue # => e
            # pp e, e.backtrace
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
