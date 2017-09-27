require 'spec_helper'
require 'yaml'

module NexusSW
  module LXD
    class Transport
      class Mock < Transport
        def initialize(config = {})
          super 'mock:', config
        end

        @@containers = {} # rubocop:disable Style/ClassVars
        @@local_files = {} # rubocop:disable Style/ClassVars
        @@remote_files = {} # rubocop:disable Style/ClassVars
        def execute_chunked(command, options)
          exitstatus = 0
          args = command.split ' '
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
                yield '/'
              when 'start'
                @@containers[args[2]]['Status'] = 'Running'
              when 'stop'
                @@containers[args[2]]['Status'] = 'Stopped'
              when 'delete' then @@containers.delete args[2]
              when 'file'
                case args[2]
                when 'push'
                  @@remote_files[args[4]] = @@local_files[args[3]]
                when 'pull'
                  @@local_files[args[4]] = @@remote_files[args[3]]
                end
              end
            end
          rescue
            exitstatus = 1
          end
          LXDExecuteResult.new(command, options, exitstatus)
        end

        def read_file(path)
          @@local_files[path] || ''
        end

        def write_file(path, content)
          @@local_files[path] = content
        end

        def download_file(path, local_path)
          File.open local_path, 'w' do |f|
            f.write @@local_files[path]
          end
        end

        def upload_file(local_path, path)
          @@local_files[path] = File.read(local_path)
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
