require 'support/mock_transport'

class Hyperkit::Mock
  def initialize
    @mock = NexusSW::LXD::Transport::Mock.new
  end

  attr_reader :mock
end
