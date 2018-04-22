$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

require "simplecov"
SimpleCov.start

require "nexussw/lxd/driver/cli"
require "nexussw/lxd/driver/rest"
require "nexussw/lxd/transport/cli"
require "nexussw/lxd/transport/rest"
require "nexussw/lxd/transport/local"
require "nexussw/lxd/version"
require "support/shared_examples"
require "support/shared_contexts"
