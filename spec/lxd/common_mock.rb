require 'spec_helper'
require 'support/mock_transport'
require 'support/mock_hk'

context 'While wrapping a Mock Transport' do
  subject(:transport) { root_transport }
  def root_transport
    NexusSW::LXD::Transport::Mock.new
  end
  describe 'CLI Driver' do
    subject(:name) { base_name }
    def base_name
      'cli-mock'
    end
    subject(:driver) { base_driver }
    def base_driver
      NexusSW::LXD::Driver::CLI.new root_transport
    end
    subject(:transport) { base_transport }
    def base_transport
      base_driver.transport_for base_name
    end
    include_context 'Driver Test', :enable_nesting_tests
  end
end
describe 'Rest Driver' do
  subject(:name) { base_name }
  def base_name
    'rest-mock'
  end
  subject(:driver) { base_driver }
  def base_driver
    NexusSW::LXD::Driver::Rest.new 'https://localhost:8443', { verify_ssl: false }, NexusSW::LXD::RestAPI::Mock.new
  end
  subject(:transport) { base_transport }
  def base_transport
    base_driver.transport_for base_name
  end
  include_context 'Driver Test', :enable_nesting_tests
end
