module NexusSW
  module LXD
    class Driver
      module Mixins
        module Helpers
          module WaitMixin
            def check_for_ip(driver, container_name)
              cc = driver.container(container_name)
              state = driver.container_state(container_name)
              cc[:expanded_devices].each do |nic, data|
                next unless data[:type] == 'nic'
                state[:network][nic][:addresses].each do |address|
                  return address[:address] if address[:family] == 'inet' && address[:address] && !address[:address].empty?
                end
              end
              nil
            end

            def wait_for(container_name, what, timeout = 60)
              Timeout.timeout timeout do
                loop do
                  retval = nil
                  case what
                  when :ip
                    retval = check_for_ip(self, container_name)
                  else
                    raise 'unrecognized option'
                  end
                  return retval if retval
                  sleep 0.5
                end
              end
            end
          end
        end
      end
    end
  end
end
