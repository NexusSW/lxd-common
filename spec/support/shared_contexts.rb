require 'support/shared_examples'

shared_context 'Root Container' do |name, driver, transport, inner_name, inner_driver, inner_transport|
  include_examples 'Container Startup', name, driver
  include_examples 'Transport Functions', transport
  it 'can set up a nested LXD' do
    expect { transport.execute('bash -c "while ! [ -a /var/lib/lxd/unix.socket ]; do sleep 1; done; lxd init --auto"').error! }.not_to raise_error
  end
  describe 'Nested CLI Interface' do
    include_examples 'Container Startup', inner_name, inner_driver
    include_examples 'Transport Functions', inner_transport
    include_examples 'Container Shutdown', inner_name, inner_driver
  end
end
