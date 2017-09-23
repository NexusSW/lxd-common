require 'spec_helper'
require 'tempfile'

shared_examples 'Container Startup' do
  it 'detects a missing container' do
    expect(test_driver.container_exists?('idontexist')).not_to be true
  end

  it 'fails creating a container with bad options' do
    expect { test_driver.create_container('iwontexist', alias: 'ubububuntu-idontexist') }.to raise_error # (Hyperkit::InternalServerError)
    expect(test_driver.container_exists?('iwontexist')).not_to be true
  end

  it 'creates a container' do
    # Requiring an image with lxd installed already, for 'easliy' testing nested containers
    expect(test_driver.create_container(test_name, alias: 'lts', server: 'https://cloud-images.ubuntu.com/releases', protocol: 'simplestreams', config: { 'security.privileged' => true, 'security.nesting' => true })).to eq test_name
  end

  it 'detects an existing container' do
    expect(test_driver.container_exists?(test_name)).to be true
  end

  it 'can start a container' do
    test_driver.start_container test_name
    expect(test_driver.container_status(test_name)).to eq 'running'
    sleep 5 # lxd gets snarky if you stop/start too fast
  end
end

shared_examples 'Transport Functions' do
  it 'can execute a command in the container' do
    expect { test_transport.execute(['ls', '-al', '/']).error! }.not_to raise_error
  end

  it 'can output to a file' do
    expect { test_transport.write_file('/tmp/rspec.tmp', File.read('.rspec')) }.not_to raise_error
  end

  it 'can upload a file' do
    expect { test_transport.upload_file('.rspec', '/tmp/rspec2.tmp') }.not_to raise_error
  end

  tfile = Tempfile.new 'lxd-rspec-tests'
  begin
    tfile.close
    it 'can download a file' do
      expect { test_transport.download_file('/tmp/rspec2.tmp', tfile.path) }.not_to raise_error
    end

    it 'can read a file' do
      expect(test_transport.read_file('/tmp/rspec.tmp')).to eq(File.read(tfile.path))
      expect(test_transport.read_file('/tmp/rspec2.tmp')).to eq(File.read('.rspec'))
    end
    # don't unlink or tfile.path gets nil'd out before the capture - just let it fall out of scope
    # ensure
    # tfile.unlink
  end
end

shared_examples 'Container Shutdown' do
  it 'can stop a container' do
    test_driver.stop_container test_name, timeout: 60, retry_interval: 5
    expect(test_driver.container_status(test_name)).to eq 'stopped'
    sleep 5 # lxd gets snarky if you stop/start too fast
  end

  it 'can start a container' do
    test_driver.start_container test_name
    expect(test_driver.container_status(test_name)).to eq 'running'
  end

  it 'can delete a running container' do
    test_driver.delete_container test_name
    expect(test_driver.container_exists?(test_name)).to be false
  end
end
