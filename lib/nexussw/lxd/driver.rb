require 'timeout'

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

      def stop_container(_container_id, _options = {})
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

      protected

      class ::Timeout::Retry < ::Timeout::Error
      end
      # Must specify :retry_interval in order to receive retries
      # And if so, then either :timeout or :retry_count must be specified
      #   :timeout == 0 without :retry_count is valid in this case, saying to retry forever
      # If nothing is specified, then this function is ineffectual and runs indefinitely
      def with_timeout_and_retries(options = {})
        Timeout.timeout(options[:timeout] || 0) do
          tries = 0
          loop do
            begin
              Timeout.timeout(options[:retry_interval] || 0, Timeout::Retry) do
                tries += 1
                return yield
              end
            rescue Timeout::Retry
              next if options[:retry_count] && (tries <= options[:retry_count])
              next if options[:timeout]
              raise
            end
          end
        end
      end
    end
  end
end
