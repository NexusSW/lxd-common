require 'nexussw/lxd'

module NexusSW
  module LXD
    class Driver
      STATUS_CODES = {
        100	=> 'created',
        101	=> 'started',
        102	=> 'stopped',
        103	=> 'running',
        104	=> 'cancelling',
        105	=> 'pending',
        106	=> 'starting',
        107	=> 'stopping',
        108	=> 'aborting',
        109	=> 'freezing',
        110	=> 'frozen',
        111	=> 'thawed',
        200	=> 'success',
        400	=> 'failure',
        401	=> 'cancelled',
      }.freeze

      def create_container(_container_name, _container_options)
        raise "#{self.class}#create_container not implemented"
      end

      def start_container(_container_id)
        raise "#{self.class}#start_container not implemented"
      end

      def stop_container(_container_id, _options = {})
        raise "#{self.class}#stop_container not implemented"
      end

      def delete_container(_container_id)
        raise "#{self.class}#delete_container not implemented"
      end

      def container_status(_container_id)
        raise "#{self.class}#container_status not implemented"
      end

      def container(_container_id)
        raise "#{self.class}#container not implemented"
      end

      def container_state(_container_id)
        raise "#{self.class}#container_state not implemented"
      end

      def wait_for(_what)
        raise "#{self.class}#wait_for not implemented"
      end

      def transport_for(_container_name)
        raise "#{self.class}#transport_for not implemented"
      end

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
