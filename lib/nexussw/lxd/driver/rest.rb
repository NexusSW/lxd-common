require 'nexussw/lxd/driver'
require 'hyperkit'

module NexusSW
  module LXD
    class Driver
      class Rest < Driver
        # PARITY note: CLI functions are on an indefinite timeout by default, yet we have a 2 minute request timeout
        # So if things start timing out in production, in the rest api, that will need increased
        # Or if the real world shows that we need a timeout on the CLI, we'll adjust that to match
        REQUEST_TIMEOUT = 60 # upstream default: 120
        def initialize(rest_endpoint, driver_options = {})
          @rest_endpoint = rest_endpoint
          hkoptions = (driver_options || {}).merge(
            api_endpoint: rest_endpoint,
            auto_sync: true
          )
          @hk = Hyperkit::Client.new(hkoptions)
          # HACK: can't otherwise get at the request timeout because sawyer is in the way
          # Beware of unused function in hyperkit: reset_agent  If that gets used it'll undo this timeout
          @hk.agent.instance_variable_get(:@conn).options[:timeout] = REQUEST_TIMEOUT
        end

        attr_reader :hk, :rest_endpoint

        def create_container(container_name, container_options = {})
          if container_exists?(container_name)
            start_container container_name # Start the container for Parity with the CLI
            return container_name
          end
          # we'll break this apart and time it out for those with slow net (and this was my 3 minute stress test case with good net)
          # parity note: CLI will run indefinitely rather than timeout hence the 0 timeout
          retval = @hk.create_container(container_name, container_options.merge(sync: false))
          LXD::with_timeout_and_retries timeout: 0 do # we'll rely on the Faraday Timeout for the retry logic so that they're not battling # , retry_interval: REQUEST_TIMEOUT do
            begin
              @hk.wait_for_operation retval[:id]
            rescue Faraday::TimeoutError => e
              raise Timeout::Retry.new e # rubocop:disable Style/RaiseArgs
            end
          end
          start_container container_name
          container_name
        end

        def start_container(container_id)
          return if container_status(container_id) == 'running'
          @hk.start_container(container_id)
          wait_for_status container_id, 'running'
        end

        def stop_container(container_id, options = {})
          return if container_status(container_id) == 'stopped'
          return @hk.stop_container(container_id, force: true) if options[:force]
          last_id = nil
          use_last = false
          LXD::with_timeout_and_retries({ timeout: 0 }.merge(options)) do # timeout: 0 to enable retry functionality
            return if container_status(container_id) == 'stopped'
            unless use_last
              # Keep resubmitting until the server complains (Stops will be ignored if init is not yet listening for SIGPWR i.e. recently started)
              begin
                last_id = @hk.stop_container(container_id, sync: false)[:id]
              rescue Hyperkit::BadRequest # Happens if a stop command has previously been accepted as well as other reasons.  handle that on next line
                raise unless last_id # if we have a last_id then a prior stop command has successfully initiated so we'll just wait on that one
                use_last = true
              end
            end
            begin
              @hk.wait_for_operation last_id # , options[:retry_interval]
            rescue Faraday::TimeoutError => e
              return if container_status(container_id) == 'stopped'
              raise Timeout::Retry.new e # if options[:retry_interval] # rubocop:disable Style/RaiseArgs
            end
          end
          wait_for_status container_id, 'stopped'
        end

        def delete_container(container_id)
          return unless container_exists? container_id
          stop_container container_id, force: true
          @hk.delete_container(container_id)
        end

        def container_status(container_id)
          STATUS_CODES[@hk.container_state(container_id)['status_code'].to_i]
        end

        def ensure_profiles(profiles = {})
          return unless profiles
          profile_list = @hk.profiles
          profiles.each do |name, profile|
            @hk.create_profile name, profile unless profile_list.index name
          end
        end

        def container(container_id)
          @hk.container container_id
        end
      end
    end
  end
end
