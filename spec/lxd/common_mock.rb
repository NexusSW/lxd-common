require 'spec_helper'
require 'support/mock_transport'

describe NexusSW::LXD::Driver::CLI do
  context NexusSW::LXD::Transport::Mock, test_nested: true do
    it_behaves_like 'Root Container'
  end
end
