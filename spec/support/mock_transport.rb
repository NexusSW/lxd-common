require 'spec_helper'
require 'yaml'

module NexusSW
  module LXD
    class Transport
      class Mock < Transport
        def initialize(config = {})
          super 'mock:', config
          @@files['local:'] ||= {}
          @@files['mock:'] ||= {}
        end

        @@containers = {} # rubocop:disable Style/ClassVars
        @@files = {} # rubocop:disable Style/ClassVars
        def split_container_name(filename)
          @@containers.each { |k, _| return [k, filename.sub(k, '')] if filename.start_with? k }
          [nil, filename]
        end

        def execute_chunked(command, options, &block)
          exitstatus = 0
          args = command.is_a?(Array) ? command : command.split(' ')
          begin
            case args[0]
            when 'lxc'
              case args[1]
              when 'info' then
                yield @@containers[args[2]].to_yaml
              when 'launch'
                exitstatus = 1 unless args[2].include? 'ubuntu:'
                @@containers[args[3]] = { 'Status' => 'Running' } if args[2].include? 'ubuntu:'
              when 'exec'
                yield('/') unless command.include? '-- lxc'
                if command.include? '-- lxc'
                  _, subcommand = command.split(' -- ', 2)
                  return execute_chunked(subcommand, options.merge(hostcontainer: args[2]), &block)
                end
              when 'start'
                @@containers[args[2]]['Status'] = 'Running'
              when 'stop'
                @@containers[args[2]]['Status'] = 'Stopped'
              when 'delete' then @@containers.delete args[2]
              when 'file'
                local = options[:hostcontainer] || 'mock:'
                localfile = ''
                remotehost, remotefile =  case args[2]
                                          when 'push'
                                            localfile = args[3]
                                            split_container_name args[4]
                                          when 'pull'
                                            localfile = args[4]
                                            split_container_name args[3]
                                          end
                case args[2]
                when 'push'
                  @@files[remotehost] ||= {}
                  @@files[remotehost][remotefile] = @@files[local][localfile]
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
          LXDExecuteResult.new(command, options, exitstatus)
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
          @@files['local:'][local_path] = @@files['mock:'][path]
        end

        def upload_file(local_path, path)
          @@files['local:'][local_path] = File.read(local_path)
          @@files['mock:'][path] = @@files['local:'][local_path]
        end
      end
    end
  end
end

# "lxc info idontexist"
# "lxc info iwontexist"
# "lxc launch ubububuntu-idontexist iwontexist"
# "lxc info iwontexist"
# "lxc info lxd-cli-driver-test"
# "lxc launch ubuntu:lts lxd-cli-driver-test -c security.privileged=true -c security.nesting=true"
# "lxc info lxd-cli-driver-test"
# "lxc info lxd-cli-driver-test"
# "lxc exec lxd-cli-driver-test -- ls -al /"
# "lxc file push C:/Users/Sean/AppData/Local/Temp/lxd-cli-driver-test20170918-5360-t1f4y3 lxd-cli-driver-test/tmp/rspec.tmp"
# "rm -rf C:/Users/Sean/AppData/Local/Temp/lxd-cli-driver-test20170918-5360-t1f4y3"
# "rm -rf C:/Users/Sean/AppData/Local/Temp/lxd-cli-driver-test20170918-5360-1u47b52"
# "lxc file pull lxd-cli-driver-test/tmp/rspec2.tmp C:/Users/Sean/AppData/Local/Temp/lxd-cli-driver-test20170918-5360-155kbcq"
# "rm -rf C:/Users/Sean/AppData/Local/Temp/lxd-cli-driver-test20170918-5360-155kbcq"
# "lxc file pull lxd-cli-driver-test/tmp/rspec.tmp C:/Users/Sean/AppData/Local/Temp/lxd-cli-driver-test20170918-5360-sldras"
# "rm -rf C:/Users/Sean/AppData/Local/Temp/lxd-cli-driver-test20170918-5360-sldras"
# "lxc info lxd-cli-driver-test"
# "lxc info lxd-cli-driver-test"
# "lxc info lxd-cli-driver-test"
# "lxc info lxd-cli-driver-test"
