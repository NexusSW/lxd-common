require 'spec_helper'

describe NexusSW::LXD::Driver do
  let(:rest_name) { 'lxd-rest-driver-test' }
  let(:rest_driver) { NexusSW::LXD::Driver::Rest.new 'https://localhost:8443', verify_ssl: false }
  let(:rest_transport) { NexusSW::LXD::Transport::Rest.new rest_driver, rest_name }
  context 'Local CLI Interface' do
    let(:test_name) { 'lxd-cli-driver-test' }
    let(:test_driver) { NexusSW::LXD::Driver::CLI.new ::NexusSW::LXD::Transport::Local.new }
    include_examples 'Container Startup'
    let(:test_transport) { NexusSW::LXD::Transport::CLI.new NexusSW::LXD::Transport::Local.new, test_name }
    include_examples 'Transport Functions'
    include_examples 'Container Shutdown'
  end
  context 'Rest Interface' do
    let(:test_name) { rest_name }
    let(:test_driver) { rest_driver }
    include_examples 'Container Startup'
    let(:test_transport) { rest_transport }
    include_examples 'Transport Functions'
    it 'can set up a nested LXD' do
      # Bootup race condition on my slow laptop - wait for socket to become available
      #
      # Got this once:
      # Failure/Error: expect { transport.execute('bash -c "lxd waitready; lxd init --auto"').error! }.not_to raise_error
      #
      #        expected no Exception, got #<RuntimeError: Error: 'bash -c "lxd waitready; lxd init --auto"' failed with exit code 1.
      #        STDERR: er...Get http://unix.socket/1.0: dial unix /var/lib/lxd/unix.socket: connect: no such file or directory
      #        > with backtrace:
      #          # ./lib/nexussw/lxd/transport.rb:36:in `error!'
      #          # ./spec/lxd/common_spec.rb:99:in `block (4 levels) in <top (required)>'
      #          # ./spec/lxd/common_spec.rb:99:in `block (3 levels) in <top (required)>'
      #
      # going back to the while loop
      #
      # expect { transport.execute('bash -c "lxd waitready; lxd init --auto"').error! }.not_to raise_error
      expect { transport.execute('bash -c "while ! [ -a /var/lib/lxd/unix.socket ]; do sleep 1; done; lxd init --auto"').error! }.not_to raise_error
    end
  end
  context 'Nested CLI Interface' do
    let(:test_name) { 'lxd-nested-cli-driver-test' }
    let(:test_driver) { NexusSW::LXD::Driver::CLI.new rest_transport }
    include_examples 'Container Startup'
    let(:test_transport) { NexusSW::LXD::Transport::CLI.new rest_transport, test_name }
    include_examples 'Transport Functions'
    include_examples 'Container Shutdown'
  end
  context 'Rest Interface - Stage 2' do
    let(:test_name) { rest_name }
    let(:test_driver) { rest_driver }
    include_examples 'Container Shutdown'
  end
end
