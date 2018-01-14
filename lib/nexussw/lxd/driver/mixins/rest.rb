require 'nexussw/lxd/rest_api'
require 'nexussw/lxd/driver/mixins/helpers/wait'
require 'nexussw/lxd/transport/rest'

module NexusSW
  module LXD
    class Driver
      module Mixins
        module Rest
          # PARITY note: CLI functions are on an indefinite timeout by default, yet we have a 2 minute socket read timeout
          # Leaving it alone, for now, on calls that are quick in nature
          # Adapting on known long running calls such as create, stop, execute
          def initialize(rest_endpoint, driver_options = {}, inner_driver = nil)
            @rest_endpoint = rest_endpoint
            @driver_options = driver_options
            apioptions = (driver_options || {}).merge(
              api_endpoint: rest_endpoint,
              auto_sync: true
            )
            @api = inner_driver || RestAPI.new(apioptions)
          end

          attr_reader :api, :rest_endpoint, :driver_options

          include Helpers::WaitMixin

          def server_info
            @server_info ||= api.get('/1.0')[:metadata]
          end

          def transport_for(container_name)
            Transport::Rest.new container_name, info: server_info, connection: api, driver_options: driver_options, rest_endpoint: rest_endpoint
          end

          def create_container(container_name, container_options = {})
            if container_exists?(container_name)
              start_container container_name # Start the container for Parity with the CLI
              return container_name
            end
            # parity note: CLI will run indefinitely rather than timeout hence the 0 timeout
            retry_forever do
              api.create_container(container_name, container_options.merge(sync: false))
            end
            start_container container_name
            container_name
          end

          def start_container(container_id)
            return if container_status(container_id) == 'running'
            retry_forever do
              api.start_container(container_id, sync: false)
            end
            wait_for_status container_id, 'running'
          end

          def stop_container(container_id, options = {})
            return if container_status(container_id) == 'stopped'
            if options[:force]
              api.stop_container(container_id, force: true)
            else
              last_id = nil
              use_last = false
              LXD.with_timeout_and_retries({ timeout: 0 }.merge(options)) do # timeout: 0 to enable retry functionality
                return if container_status(container_id) == 'stopped'
                begin
                  unless use_last
                    # Keep resubmitting until the server complains (Stops will be ignored/hang if init is not yet listening for SIGPWR i.e. recently started)
                    begin
                      last_id = api.stop_container(container_id, sync: false)[:metadata][:id]
                    rescue Hyperkit::BadRequest # Happens if a stop command has previously been accepted as well as other reasons.  handle that on next line
                      # if we have a last_id then a prior stop command has successfully initiated so we'll just wait on that one
                      raise unless last_id # rubocop:disable Metrics/BlockNesting
                      use_last = true
                    end
                  end
                  api.wait_for_operation last_id # , options[:retry_interval]
                rescue Faraday::TimeoutError => e
                  return if container_status(container_id) == 'stopped'
                  raise Timeout::Retry.new e # if options[:retry_interval] # rubocop:disable Style/RaiseArgs
                end
              end
            end
            wait_for_status container_id, 'stopped'
          end

          def delete_container(container_id)
            return unless container_exists? container_id
            stop_container container_id, force: true

            # ISSUE 17: something upstream is causing a double-tap on the REST endpoint

            # trial return to normal
            # begin
            api.delete_container container_id
            # rescue ::Faraday::ConnectionFailed, ::Hyperkit::BadRequest
            #   LXD.with_timeout_and_retries timeout: 120 do
            #     loop do
            #       return unless container_exists? container_id
            #       sleep 0.3
            #     end
            #   end
            # end
          end

          def container_status(container_id)
            STATUS_CODES[api.container(container_id)[:metadata][:status_code].to_i]
          end

          def container_state(container_id)
            return nil unless container_status(container_id) == 'running' # Parity with CLI
            api.container_state(container_id)[:metadata]
          end

          def container(container_id)
            api.container(container_id)[:metadata]
          end

          def container_exists?(container_id)
            api.containers[:metadata].map { |url| url.split('/').last }.include? container_id
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
                api.wait_for_operation retval[:metadata][:id]
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
