require "nexussw/lxd/transport"
require "nexussw/lxd/transport/mixins/local"

module NexusSW
  module LXD
    class Transport
      class Local < Transport
        include Mixins::Local
      end
    end
  end
end
