require 'spec_helper'

describe NexusSW::LXD::Driver do
  let(:test_name) { 'lxd-driver-test' }
  let(:nx_driver) { NexusSW::LXD::Driver::Rest.new 'https://localhost:8443', verify_ssl: false }

  context 'Rest Interface' do
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

    context 'Rest Transport' do
      let(:transport) { driver.transport_strategy.guest_transport(test_name) }

      it 'can execute a command in the container' do
        expect { transport.execute(['ls', '-al', '/']).error! }.not_to raise_error
      end

      it 'remaps localhost to an adapter ip' do
        expect(transport.make_url_available_to_remote('chefzero://localhost:1234')).not_to include('localhost')
        expect(transport.make_url_available_to_remote('chefzero://127.0.0.1:1234')).not_to include('127.0.0.1')
      end

      it 'can output to a file' do
        expect { transport.write_file('/tmp/somerandomfile.tmp', 'some random content') }.not_to raise_error
      end

      it 'can upload a file' do
        expect { transport.upload_file('/etc/passwd', '/tmp/passwd.tmp') }.not_to raise_error
      end

      it 'can download a file' do
        expect { transport.download_file('/etc/group', '/tmp/rspectest.tmp') }.not_to raise_error
      end

      it 'can read a file' do
        expect(transport.read_file('/tmp/passwd.tmp')).to include('root:')
      end
    end if false

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
