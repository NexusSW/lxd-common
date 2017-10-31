require 'support/shared_examples'

shared_context 'Nesting' do
  it 'can set up a nested LXD' do
    expect { transport.execute('bash -c "while ! [ -a /var/lib/lxd/unix.socket ]; do sleep 1; done; lxd init --auto"').error! }.not_to raise_error
  end
  describe 'Nested CLI Driver' do
    subject(:name) { 'nested-' + base_name }
    subject(:driver) { Driver::CLI.new base_transport }
    include_context 'it can create containers'
    context 'Nested CLI Transport' do
      subject(:transport) { Transport::CLI.new base_transport, name }
      include_context 'Transport Functions'
    end
    it_behaves_like 'it can teardown a container'
  end
end

shared_context 'Driver Test' do |enable_nesting_tests = false|
  include_examples 'it can create containers'
  context 'Transport' do
    include_examples 'Transport Functions'
    include_context 'Nesting' if enable_nesting_tests
  end
  it_behaves_like 'it can teardown a container'
end
