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
          container_name
        end

        def start_container(container_id)
          return if container_status(container_id) == 'running'
          @hk.start_container(container_id)
          waitforstatus container_id, 'running'
        end

        def stop_container(container_id)
          return if container_status(container_id) == 'stopped'
          @hk.stop_container(container_id)
          waitforstatus container_id, 'stopped'
        end

        def delete_container(container_id)
          return unless container_exists? container_id
          @hk.stop_container(container_id, force: true) unless container_status(container_id) == 'stopped'
          waitforstatus container_id, 'stopped'
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

        private

        # TODO: add timeout
        def waitforstatus(container_id, newstatus)
          loop do
            status = container_status(container_id)
            break if status == newstatus
            sleep 0.5
          end
        end
      end
    end
  end
end
