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
        raise 'NexusSW::LXD::Driver.create_container not implemented'
      end

      def start_container(_container_id)
        raise 'NexusSW::LXD::Driver.start_container not implemented'
      end

      def stop_container(_container_id)
        raise 'NexusSW::LXD::Driver.stop_container not implemented'
      end

      def delete_container(_container_id)
        raise 'NexusSW::LXD::Driver.delete_container not implemented'
      end

      def container_status(_container_id)
        raise 'NexusSW::LXD::Driver.container_status not implemented'
      end

      def ensure_profiles(_profiles)
        raise 'NexusSW::LXD::Driver.ensure_profiles not implemented'
      end

      def container(_container_id)
        raise 'NexusSW::LXD::Driver.container not implemented'
      end

      def container_exists?(container_id)
        return true if container_status(container_id)
        return false
      rescue
        false
      end

      def container_hostname(container_id)
        container_id
      end
    end
  end
end
