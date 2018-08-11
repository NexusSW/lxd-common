require "nexussw/lxd"

module NexusSW
  module LXD
    class Driver
      STATUS_CODES = {
        100	=> "created",
        101	=> "started",
        102	=> "stopped",
        103	=> "running",
        104	=> "cancelling",
        105	=> "pending",
        106	=> "starting",
        107	=> "stopping",
        108	=> "aborting",
        109	=> "freezing",
        110	=> "frozen",
        111	=> "thawed",
        200	=> "success",
        400	=> "failure",
        401	=> "cancelled",
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

      def update_container(_container_name, _container_options)
        raise "#{self.class}#update_container not implemented"
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

      def wait_for(_container_name, _what, _timeout = 60)
        raise "#{self.class}#wait_for not implemented"
      end

      def transport_for(_container_name)
        raise "#{self.class}#transport_for not implemented"
      end

      # Image examples:
      # - driver.image.import(...)
      # - driver.image[image_alias_or_fingerprint].export(...)
      # - driver.image[image_alias_or_fingerprint].info(...) # <-- get and set

      def images
        raise "#{self.class}#images not implemented"
      end

      def self.convert_bools(oldhash)
        {}.tap do |retval|
          oldhash.each do |k, v|
            retval[k] = case v
                        when "true" then true
                        when "false" then false
                        else v.is_a?(Hash) ? convert_bools(v) : v
                        end
          end
        end
      end
    end
  end
end
