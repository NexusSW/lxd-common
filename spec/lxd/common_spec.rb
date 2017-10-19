require 'spec_helper'
require 'support/mock_transport'

# NIO::WebSocket::log_traffic = true
describe 'Rest Driver' do
  subject(:name) { base_name }
  def base_name
    'rest-local'
  end
  subject(:driver) { base_driver }
  def base_driver
    NexusSW::LXD::Driver::Rest.new 'https://localhost:8443', verify_ssl: false
  end
  subject(:transport) { base_transport }
  def base_transport
    NexusSW::LXD::Transport::Rest.new base_driver, base_name
  end
  include_context 'Driver Test', :enable_nesting_tests
end
context 'While wrapping a Local Transport' do
  subject(:transport) { root_transport }
  def root_transport
    NexusSW::LXD::Transport::Local.new
  end
  describe 'CLI Driver' do
    subject(:name) { base_name }
    def base_name
      'cli-local'
    end
    subject(:driver) { base_driver }
    def base_driver
      NexusSW::LXD::Driver::CLI.new root_transport
    end
    subject(:transport) { base_transport }
    def base_transport
      NexusSW::LXD::Transport::CLI.new root_transport, base_name
    end
    include_context 'Driver Test', :enable_nesting_tests
  end
end
