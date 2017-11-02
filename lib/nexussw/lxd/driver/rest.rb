require 'nexussw/lxd/driver'
require 'nexussw/lxd/driver/mixins/rest'

module NexusSW
  module LXD
    class Driver
      class Rest < Driver
        include Mixins::Rest
      end
    end
  end
end
