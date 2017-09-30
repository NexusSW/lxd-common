require 'support/shared_examples'

shared_context 'Container Control' do
  include_examples 'Container Startup'
end

shared_context 'Container User' do
  include_examples 'Transport Functions'
end

shared_context 'Container Teardown' do
  include_examples 'Container Shutdown'
end

shared_context 'Nesting Config' do
  it 'can set up a nested LXD' do
    expect { transport.execute('bash -c "while ! [ -a /var/lib/lxd/unix.socket ]; do sleep 1; done; lxd init --auto"').error! }.not_to raise_error
  end
end
