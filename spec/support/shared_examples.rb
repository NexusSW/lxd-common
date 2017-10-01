require 'tempfile'

shared_examples 'it can create containers' do
  it 'detects a missing container' do
    expect(driver.container_exists?('idontexist')).not_to be true
  end

  it 'fails creating a container with bad options' do
    expect { driver.create_container('iwontexist', alias: 'ubububuntu-idontexist') }.to raise_error # (Hyperkit::InternalServerError)
    expect(driver.container_exists?('iwontexist')).not_to be true
  end

  it 'creates a container' do
    # Requiring an image with lxd installed already, for 'easliy' testing nested containers
    expect(driver.create_container(name, alias: 'lts', server: 'https://cloud-images.ubuntu.com/releases', protocol: 'simplestreams', config: { 'security.privileged' => true, 'security.nesting' => true })).to eq name
    sleep 5 # woah up to help with some startup race conditions - intentionally punting the same issues to the consumer
    expect(driver.container_status(name)).to eq('running') # TBD - find some way to avoid the sleep call - maybe tie into cloud init if i can convince myself to lock this test to containers that support that
  end

  it 'detects an existing container' do
    expect(driver.container_exists?(name)).to be true
  end
end

shared_examples 'Transport Functions' do
  it 'can execute a command in a container' do
    # expect { transport.execute(['ls', '-al', '/']).error! }.not_to raise_error
    expect(transport.execute(['ls', '-al', '/']).error!.stdout.length).to satisfy { |l| l > 0 }
  end

  it 'can output to a file' do
    expect { transport.write_file('/tmp/rspec.tmp', File.read('.rspec')) }.not_to raise_error
    expect(transport.read_file('/tmp/rspec.tmp')).to eq(File.read('.rspec'))
  end

  it 'can upload a file' do
    expect { transport.upload_file('.rspec', '/tmp/rspec2.tmp') }.not_to raise_error
    expect(transport.read_file('/tmp/rspec2.tmp')).to eq(File.read('.rspec'))
  end

  tfile = Tempfile.new 'lxd-rspec-tests'
  begin
    tfile.close
    it 'can download a file' do
      expect { transport.download_file('/tmp/rspec2.tmp', tfile.path) }.not_to raise_error
      expect(File.read(tfile.path)).to eq(File.read('.rspec'))
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

shared_examples 'it can teardown a container' do
  it 'can stop a container' do
    expect { driver.stop_container name, timeout: 60, retry_interval: 5 }.not_to raise_error
    expect(driver.container_status(name)).to eq 'stopped'
  end

  it 'can start a container' do
    expect { driver.start_container name }.not_to raise_error
    expect(driver.container_status(name)).to eq 'running'
  end

  it 'can delete a running container' do
    expect { driver.delete_container name }.not_to raise_error
    expect(driver.container_exists?(name)).to be false
  end
end
