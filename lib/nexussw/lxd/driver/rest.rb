require 'nexussw/lxd/driver'
require 'hyperkit'

module NexusSW
  module LXD
    class Driver
      class Rest < Driver
        def initialize(rest_endpoint, driver_options = {})
          hkoptions = (driver_options || {}).merge(
            api_endpoint: rest_endpoint,
            auto_sync: true
          )
          @hk = Hyperkit::Client.new(hkoptions)
        end

        attr_reader :hk

        def create_container(container_name, container_options = {})
          return if container_exists?(container_name)
          @hk.create_container(container_name, container_options)
          start_container container_name
          container_name
        end

        def start_container(container_id)
          return if container_status(container_id) == 'running'
          @hk.start_container(container_id)
        end

        # <Hyperkit::BadRequest: 400 - Error: >
        def stop_container(container_id, options = {})
          options ||= {}
          with_timeout_and_retries(options) do
            return if container_status(container_id) == 'stopped'
            begin
              myopts = {}
              myopts[:force] = options[:force] if options.key? :force
              myopts[:timeout] = (options[:retry_interval] * 2) if options.key?(:retry_interval) && options[:retry_interval] > 0
              @hk.stop_container container_id, myopts
            rescue Hyperkit::BadRequest
              return if container_status(container_id) == 'stopped'
              raise
            end
          end
        rescue Timeout::Error
          return if container_status(container_id) == 'stopped'
          return @hk.stop_container(container_id, force: true) if options[:force]
          raise
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
