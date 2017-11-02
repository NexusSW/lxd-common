require 'nexussw/lxd/driver'
require 'nexussw/lxd/driver/mixins/cli'

module NexusSW
  module LXD
    class Driver
      class CLI < Driver
        include Mixins::CLI
      end
    end
  end
end
