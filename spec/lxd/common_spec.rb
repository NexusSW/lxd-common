require 'spec_helper'
require 'tempfile'

describe NexusSW::LXD::Driver do
  let(:test_name) { 'lxd-driver-test' }
  let(:nx_driver) { NexusSW::LXD::Driver::CLI.new ::NexusSW::LXD::Transport::Local.new }

  context 'Local CLI Interface' do
    it 'detects a missing container' do
      expect(nx_driver.container_exists?('idontexist')).not_to be true
    end

    it 'fails creating a container with bad options' do
      expect { nx_driver.create_container('iwontexist', alias: 'ubububuntu-idontexist') }.to raise_error # (Hyperkit::InternalServerError)
    end

    it 'creates a container' do
      expect(nx_driver.create_container(test_name, alias: 'lts', server: 'https://cloud-images.ubuntu.com/releases', protocol: 'simplestreams')).to eq test_name
    end

    it 'detects an existing container' do
      expect(nx_driver.container_exists?(test_name)).to be true
    end

    it 'can start a container' do
      nx_driver.start_container test_name
      expect(nx_driver.container_status(test_name)).to eq 'running'
    end

    let(:transport) { NexusSW::LXD::Transport::CLI.new nx_driver, NexusSW::LXD::Transport::Local.new, test_name }

    it 'can execute a command in the container' do
      expect { transport.execute(['ls', '-al', '/']).error! }.not_to raise_error
    end

    it 'can output to a file' do
      expect { transport.write_file('/tmp/somerandomfile.tmp', 'some random content') }.not_to raise_error
    end

    it 'can upload a file' do
      expect { transport.upload_file('.rspec', '/tmp/rspec.tmp') }.not_to raise_error
    end

    tfile = Tempfile.new 'lxd-rspec-tests'
    begin
      tfile.close
      it 'can download a file' do
        expect { transport.download_file('/tmp/rspec.tmp', tfile.path) }.not_to raise_error
      end

      it 'can read a file' do
        expect(transport.read_file('/tmp/rspec.tmp')).to eq(File.read(tfile.path))
      end
      # don't unlink or tfile.path gets nil'd out before the capture - just let it fall out of scope
      # ensure
      # tfile.unlink
    end

    it 'can stop a container' do
      nx_driver.stop_container test_name
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
end
