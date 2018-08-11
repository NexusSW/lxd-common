# Image examples:
# - driver.image.import(...)
# - driver.image[image_alias_or_fingerprint].export(...)
# - driver.image[image_alias_or_fingerprint].info(...) # <-- get and set

require "nexussw/lxd/driver"

module NexusSW
  module LXD
    class Driver
      class Images
        def [](alias_or_fingerprint)
          fingerprint = map_alias(alias_or_fingerprint)
          raise RestAPI::Error::NotFound, "Image alias (#{alias_or_fingerprint}) not found" unless fingerprint
          handlers[fingerprint] ||= handler_for(fingerprint)
        end

        # caller may/must supply metadata if any is desired.  the source has no info
        # if a file:// url is used, it refers locally
        def download(source, options = {})
          raise "#{self.class}#download not implemented"
        end

        # create from an existing container
        def create_from(container_name, options = {})
          raise "#{self.class}#create_from not implemented"
        end

        protected

        def handler_for(alias_or_fingerprint)
          raise "#{self.class}#handler_for not implemented"
        end

        def map_alias(alias_or_fingerprint)
          raise "#{self.class}#map_alias not implemented"
        end

        private

        def handlers
          @handlers ||= {}
        end

        class ImageHandler
          # export, with metadata, to the specified host
          def export(destination, options = {})
            raise "#{self.class}#export not implemented"
          end

          # export to a file or stream
          def save(filename, options = {})
            raise "#{self.class}#save not implemented"
          end

          def refresh(filename, options = {})
            raise "#{self.class}#refresh not implemented"
          end

          def delete
            raise "#{self.class}#delete not implemented"
          end

          def exist?
            raise "#{self.class}#exist? not implemented"
          end
        end
      end
    end
  end
end
