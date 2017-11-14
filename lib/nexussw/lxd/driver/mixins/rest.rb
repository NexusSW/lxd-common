require 'nexussw/lxd/driver/mixins/helpers/wait'
require 'hyperkit'

module NexusSW
  module LXD
    class Driver
      module Mixins
        module Rest
          # PARITY note: CLI functions are on an indefinite timeout by default, yet we have a 2 minute socket read timeout
          # Leaving it alone, for now, on calls that are quick in nature
          # Adapting on known long running calls such as create, stop, execute
          # REQUEST_TIMEOUT = 120 # upstream default: 120
          def initialize(rest_endpoint, driver_options = {}, inner_driver = nil)
            @rest_endpoint = rest_endpoint
            @driver_options = driver_options
            hkoptions = (driver_options || {}).merge(
              api_endpoint: rest_endpoint,
              auto_sync: true
            )
            @hk = inner_driver || Hyperkit::Client.new(hkoptions)
          end

          attr_reader :hk, :rest_endpoint, :driver_options

          include Helpers::WaitMixin

          def server_info
            @server_info ||= hk.get('/1.0')[:metadata]
          end

          def transport_for(container_name)
            Transport::Rest.new container_name, info: server_info, connection: hk, driver_options: driver_options, rest_endpoint: rest_endpoint
          end

          def create_container(container_name, container_options = {})
            if container_exists?(container_name)
              start_container container_name # Start the container for Parity with the CLI
              return container_name
            end
            # parity note: CLI will run indefinitely rather than timeout hence the 0 timeout
            retry_forever do
              @hk.create_container(container_name, container_options.merge(sync: false))
            end
            start_container container_name
            container_name
          end

          def start_container(container_id)
            return if container_status(container_id) == 'running'
            retry_forever do
              @hk.start_container(container_id, sync: false)
            end
            wait_for_status container_id, 'running'
          end

          def stop_container(container_id, options = {})
            return if container_status(container_id) == 'stopped'
            return @hk.stop_container(container_id, force: true) if options[:force]
            last_id = nil
            use_last = false
            LXD.with_timeout_and_retries({ timeout: 0 }.merge(options)) do # timeout: 0 to enable retry functionality
              return if container_status(container_id) == 'stopped'
              begin
                unless use_last
                  # Keep resubmitting until the server complains (Stops will be ignored/hang if init is not yet listening for SIGPWR i.e. recently started)
                  begin
                    last_id = @hk.stop_container(container_id, sync: false)[:id]
                  rescue Hyperkit::BadRequest # Happens if a stop command has previously been accepted as well as other reasons.  handle that on next line
                    raise unless last_id # if we have a last_id then a prior stop command has successfully initiated so we'll just wait on that one
                    use_last = true
                  end
                end
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
            STATUS_CODES[container(container_id)[:status_code].to_i]
          end

          def container_state(container_id)
            return nil unless container_status(container_id) == 'running' # Parity with CLI
            @hk.container_state(container_id)
          end

          def container(container_id)
            @hk.container container_id
          end

          def container_exists?(container_id)
            return true if container_status(container_id)
            return false
          rescue
            false
          end

          protected

          def wait_for_status(container_id, newstatus)
            loop do
              return if container_status(container_id) == newstatus
              sleep 0.5
            end
          end

          private

          def retry_forever
            retval = yield
            LXD.with_timeout_and_retries timeout: 0 do
              begin
                @hk.wait_for_operation retval[:id]
              rescue Faraday::TimeoutError => e
                raise Timeout::Retry.new e # rubocop:disable Style/RaiseArgs
              end
            end
          end
        end
      end
    end
  end
end
