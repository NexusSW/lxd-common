require 'spec_helper'

describe NexusSW::LXD::Driver do
  context 'Local CLI' do
    include_context 'Root Container' do
      let(:test_name) { 'lxd-cli-driver-test' }
      let(:test_driver) { NexusSW::LXD::Driver::CLI.new ::NexusSW::LXD::Transport::Local.new }
      let(:test_transport) { NexusSW::LXD::Transport::CLI.new NexusSW::LXD::Transport::Local.new, test_name }
      let(:inner_name) { 'lxd-nested-cli-cli-driver-test' }
      let(:inner_driver) { NexusSW::LXD::Driver::CLI.new test_transport }
      let(:inner_transport) { NexusSW::LXD::Transport::CLI.new test_transport, inner_name }
    end
  end
  context 'Rest' do
    include_context 'Root Container' do
      let(:test_name) { 'lxd-rest-driver-test' }
      let(:rest_driver) { NexusSW::LXD::Driver::Rest.new 'https://localhost:8443', verify_ssl: false }
      let(:rest_transport) { NexusSW::LXD::Transport::Rest.new rest_driver, rest_name }
      let(:inner_name) { 'lxd-nested-rest-cli-driver-test' }
      let(:inner_driver) { NexusSW::LXD::Driver::CLI.new test_transport }
      let(:inner_transport) { NexusSW::LXD::Transport::CLI.new test_transport, inner_name }
    end
  end
end
