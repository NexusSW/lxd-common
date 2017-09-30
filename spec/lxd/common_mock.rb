require 'spec_helper'
require 'support/mock_transport'

context NexusSW::LXD::Transport::Mock do
  subject(:transport) { root_transport }
  def root_transport
    # transport
    NexusSW::LXD::Transport::Mock.new
  end
  describe NexusSW::LXD::Driver::CLI do
    subject(:name) { base_name }
    def base_name
      'mock-cli-test'
    end
    subject(:driver) { base_driver }
    def base_driver
      NexusSW::LXD::Driver::CLI.new root_transport
    end
    it_behaves_like 'Container Control'
    context NexusSW::LXD::Transport::CLI do
      subject(:transport) { base_transport }
      def base_transport
        NexusSW::LXD::Transport::CLI.new root_transport, base_name
      end
      include_context 'Container User'
      include_context 'Nesting Config'
      describe 'Nested Container Control' do
        subject(:name) { 'nested-mock-cli-test' }
        subject(:driver) { NexusSW::LXD::Driver::CLI.new base_transport }
        include_context 'Container Control'
        context 'Nested Transport' do
          subject(:transport) { NexusSW::LXD::Transport::CLI.new base_transport, name }
          include_context 'Container User'
        end
        it_behaves_like 'Container Teardown'
      end
    end
    it_behaves_like 'Container Teardown'
  end
end
