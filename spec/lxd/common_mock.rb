require 'spec_helper'
require 'mock_transport'

describe NexusSW::LXD::Driver do
  context 'Local CLI Interface' do
    let(:test_name) { 'lxd-cli-driver-test' }
    let(:nx_driver) { NexusSW::LXD::Driver::CLI.new ::NexusSW::LXD::Transport::Mock.new }
    include_examples 'Container Startup'
    let(:transport) { NexusSW::LXD::Transport::CLI.new NexusSW::LXD::Transport::Mock.new, test_name }
    include_examples 'Transport Functions'
    include_examples 'Container Shutdown'
  end
end
