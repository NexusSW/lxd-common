require 'nexussw/lxd/transport'
require 'nexussw/lxd/transport/mixins/cli'

module NexusSW
  module LXD
    class Transport
      class CLI < Transport
        include Mixins::CLI
      end
    end
  end
end
