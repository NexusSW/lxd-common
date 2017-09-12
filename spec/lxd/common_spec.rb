require 'spec_helper'
require 'tempfile'

shared_examples 'Container Startup' do
  it 'detects a missing container' do
    expect(nx_driver.container_exists?('idontexist')).not_to be true
  end

  it 'fails creating a container with bad options' do
    expect { nx_driver.create_container('iwontexist', alias: 'ubububuntu-idontexist') }.to raise_error # (Hyperkit::InternalServerError)
  end

  it 'creates a container' do
    # Requiring an image with lxd installed already, for 'easliy' testing nested containers
    expect(nx_driver.create_container(test_name, alias: 'lts', server: 'https://cloud-images.ubuntu.com/releases', protocol: 'simplestreams', config: { 'security.privileged' => true, 'security.nesting' => true })).to eq test_name
  end

  it 'detects an existing container' do
    expect(nx_driver.container_exists?(test_name)).to be true
  end

  it 'can start a container' do
    nx_driver.start_container test_name
    expect(nx_driver.container_status(test_name)).to eq 'running'
    sleep 5
  end
end

shared_examples 'Transport Functions' do
  it 'can execute a command in the container' do
    expect { transport.execute(['ls', '-al', '/']).error! }.not_to raise_error
  end

  it 'can output to a file' do
    expect { transport.write_file('/tmp/rspec.tmp', File.read('.rspec')) }.not_to raise_error
  end

  it 'can upload a file' do
    expect { transport.upload_file('.rspec', '/tmp/rspec2.tmp') }.not_to raise_error
  end

  tfile = Tempfile.new 'lxd-rspec-tests'
  begin
    tfile.close
    it 'can download a file' do
      expect { transport.download_file('/tmp/rspec2.tmp', tfile.path) }.not_to raise_error
    end

    it 'can read a file' do
      expect(transport.read_file('/tmp/rspec.tmp')).to eq(File.read(tfile.path))
      expect(transport.read_file('/tmp/rspec2.tmp')).to eq(File.read('.rspec'))
    end
    # don't unlink or tfile.path gets nil'd out before the capture - just let it fall out of scope
    # ensure
    # tfile.unlink
  end
end

shared_examples 'Container Shutdown' do
  it 'can stop a container' do
    nx_driver.stop_container test_name, timeout: 60, retry_interval: 2
    expect(nx_driver.container_status(test_name)).to eq 'stopped'
  end

  it 'can start a container' do
    nx_driver.start_container test_name
    expect(nx_driver.container_status(test_name)).to eq 'running'
  end

  it 'can delete a running container' do
    nx_driver.delete_container test_name
    expect(nx_driver.container_exists?(test_name)).to be false
  end
end

describe NexusSW::LXD::Driver do
  let(:rest_name) { 'lxd-rest-driver-test' }
  let(:rest_driver) { NexusSW::LXD::Driver::Rest.new 'https://localhost:8443', verify_ssl: false }
  let(:rest_transport) { NexusSW::LXD::Transport::Rest.new rest_driver, rest_name }
  context 'Local CLI Interface' do
    let(:test_name) { 'lxd-cli-driver-test' }
    let(:nx_driver) { NexusSW::LXD::Driver::CLI.new ::NexusSW::LXD::Transport::Local.new }
    include_examples 'Container Startup'
    let(:transport) { NexusSW::LXD::Transport::CLI.new nx_driver, NexusSW::LXD::Transport::Local.new, test_name }
    include_examples 'Transport Functions'
    include_examples 'Container Shutdown'
  end
  context 'Rest Interface' do
    let(:test_name) { rest_name }
    let(:nx_driver) { rest_driver }
    include_examples 'Container Startup'
    let(:transport) { rest_transport }
    include_examples 'Transport Functions'
    it 'can set up a nested LXD' do
      # Bootup race condition on my slow laptop - wait for socket to become available
      expect { transport.execute('bash -c "while ! [ -a /var/lib/lxd/unix.socket ]; do sleep 1; done; lxd init --auto"').error! }.not_to raise_error
    end
  end
  context 'Nested CLI Interface' do
    let(:test_name) { 'lxd-nested-cli-driver-test' }
    let(:nx_driver) { NexusSW::LXD::Driver::CLI.new rest_transport }
    include_examples 'Container Startup'
    let(:transport) { NexusSW::LXD::Transport::CLI.new nx_driver, rest_transport, test_name }
    include_examples 'Transport Functions'
    include_examples 'Container Shutdown'
  end
  context 'Rest Interface - Stage 2' do
    let(:test_name) { rest_name }
    let(:nx_driver) { rest_driver }
    include_examples 'Container Shutdown'
  end
end
