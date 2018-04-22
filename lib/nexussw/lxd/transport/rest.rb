require "nexussw/lxd/transport"
require "nexussw/lxd/transport/mixins/rest"

module NexusSW
  module LXD
    class Transport
      class Rest < Transport
        include Mixins::Rest
      end
    end
  end
end
