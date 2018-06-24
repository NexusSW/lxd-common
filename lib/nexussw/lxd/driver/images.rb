# Image examples:
# - driver.image.import(...)
# - driver.image[image_alias_or_fingerprint].export(...)
# - driver.image[image_alias_or_fingerprint].info(...) # <-- get and set

require "nexussw/lxd/driver"

module NexusSW
  module LXD
    class Driver
      class Images
        def [](name_or_fingerprint)
          handlers[name_or_fingerprint] ||= handler_for(name_or_fingerprint)
        end

        def import(source, options = {})
          raise "#{self.class}#import not implemented"
        end

        # allow file:// url's for http post, or otherwise submit url to server for download
        def download(source, options = {})
          raise "#{self.class}#download not implemented"
        end

        def create_from(container_name, options = {})
          raise "#{self.class}#create_from not implemented"
        end

        protected

        def handler_for(name_or_fingerprint)
          raise "#{self.class}#handler_for not implemented"
        end

        private

        def handlers
          @handlers ||= {}
        end

        class ImageHandler
          def export(options = {})
            raise "#{self.class}#export not implemented"
          end

          def save(filename, options = {})
            raise "#{self.class}#save not implemented"
          end

          def delete
            raise "#{self.class}#delete not implemented"
          end
        end
      end
    end
  end
end
