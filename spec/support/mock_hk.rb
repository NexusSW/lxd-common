require 'support/mock_transport'

module NexusSW::Hyperkit
  class Mock
    def initialize
      @mock = NexusSW::LXD::Transport::Mock.new
    end

    attr_reader :mock
  end
end
