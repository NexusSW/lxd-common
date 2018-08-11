require "tempfile"
require "fileutils"

shared_examples "it can create containers" do
  it "detects a missing container" do
    expect(driver.container_exists?("idontexist")).not_to be true
  end

  it "fails creating a container with bad options" do
    expect { driver.create_container("iwontexist", alias: "ubububuntu-idontexist") }.to raise_error(::NexusSW::LXD::RestAPI::Error)
    expect(driver.container_exists?("iwontexist")).not_to be true
  end

  it "creates a container" do
    # Requiring an image with lxd installed already, for 'easliy' testing nested containers
    expect(driver.create_container(name, alias: "lts", server: "https://cloud-images.ubuntu.com/releases", protocol: "simplestreams", config: { "security.privileged" => true, "security.nesting" => true })).to eq name
    expect(driver.container_status(name)).to eq("running")
  end

  it "updates a container" do
    results = driver.update_container(name, config: { "security.idmap.isolated" => true })
    expect(results[:config]).to include("security.idmap.isolated" => true)
    expect(results[:config]).to include("security.nesting" => true) # Ensure deep merge
  end

  it "detects an existing container" do
    expect(driver.container_exists?(name)).to be true
  end

  it "queries container information" do
    container = driver.container(name)
    expect(container).not_to be nil
    expect(container.key?(:state)).to be false
    expect(container.key?(:status_code)).to be true

    state = driver.container_state(name)
    expect(state).not_to be nil
    expect(state.key?(:status_code)).to be true
  end
end

shared_examples "Transport Functions" do
  subject(:transport) { driver.transport_for name }

  it "can execute a command in a container" do
    # expect { transport.execute(['ls', '-al', '/']).error! }.not_to raise_error
    expect(transport.execute(["ls", "-al", "/"]).error!.stdout.length).to satisfy { |l| l > 0 }
  end

  it "can execute a command interactively" do
    data = ""
    expect do
      transport.execute("/bin/bash", capture: :interactive, tty: false) do |active|
        active.capture_output do |stdout|
          data += stdout if stdout
        end
        active.stdin.write "ls -al /\nexit\n"
        sleep 1
      end.error!
    end.not_to raise_error
    expect(data.length).to satisfy { |l| l > 0 }
    expect(data.lines).to include(/ home[\r]?$/)
  end

  it "can output to a file" do
    expect { transport.write_file("/root/rspec.tmp", File.read(".rspec")) }.not_to raise_error
    expect(transport.read_file("/root/rspec.tmp")).to eq(File.read(".rspec"))
  end

  it "can upload a file" do
    expect { transport.upload_file(".rspec", "/root/rspec2.tmp") }.not_to raise_error
    expect(transport.read_file("/root/rspec2.tmp")).to eq(File.read(".rspec"))
  end

  it "can upload a folder" do
    expect { transport.upload_folder("spec", "/root") }.not_to raise_error
    expect(transport.read_file("/root/spec/support/shared_contexts.rb")).to eq(File.read("spec/support/shared_contexts.rb"))
  end

  it "can download a folder" do
    begin
      localname = File.join(::NexusSW::LXD::Transport.local_tempdir, "spec")
      expect { transport.download_folder("/root/spec", File.dirname(localname)) }.not_to raise_error
      expect(File.read(File.join(localname, "support/shared_contexts.rb"))).to eq(File.read("spec/support/shared_contexts.rb"))
    ensure
      FileUtils.rm_rf localname, secure: true
    end
  end

  tfile = Tempfile.new "lxd-rspec-tests"
  begin
    tfile.close
    it "can download a file" do
      expect { transport.download_file("/root/rspec2.tmp", tfile.path) }.not_to raise_error
      expect(File.read(tfile.path)).to eq(File.read(".rspec"))
    end

    it "can read a file" do
      expect(transport.read_file("/root/rspec.tmp")).to eq(File.read(tfile.path))
      expect(transport.read_file("/root/rspec2.tmp")).to eq(File.read(".rspec"))
    end
    # don't unlink or tfile.path gets nil'd out before the capture - just let it fall out of scope
    # ensure
    # tfile.unlink
  end
end

shared_examples "it can teardown a container" do
  it "can stop a container" do
    expect { driver.stop_container name, timeout: 60, retry_interval: 5 }.not_to raise_error
    expect(driver.container_status(name)).to eq "stopped"
  end

  it "can start a container" do
    expect { driver.start_container name }.not_to raise_error
    expect(driver.container_status(name)).to eq "running"
  end

  it "can delete a running container" do
    expect { driver.delete_container name }.not_to raise_error
    expect(driver.container_exists?(name)).to be false
  end
end

=begin
create from container
export
download
save (to file)
delete
=end
shared_examples "it can manage images" do

  let(:image_name) { "image-from-#{name}" }
  let(:image_file) { Dir.pwd + "/image-testfile-#{name}" }
  let(:remote_image_name) { "remote-image-from-#{base_name}" }

  it "can create an image from a container" do
    driver.stop_container name, force: true
    expect(driver.images.create_from(name, aliases: [{name: image_name}])).to have_key(:aliases)
    driver.start_container name
  end

  it "can export an image to a file" do
    driver.images[image_name].save(image_file)
    expect(File.exist?(image_file) && !File.zero?(image_file)).to be true
  end

  # covering REST#download
  it "can import an image from a file" do
    driver.images.download "file://" + image_file, aliases: [{name: remote_image_name}]
    expect(driver.images[remote_image_name].exist?).to be true
  end

  # covering REST being the destination of #export
end

# this is run on a nested container
# any commands sent to the nested container will still need tested in another context (to ensure the rest driver is covered)
shared_examples "it can transfer images" do
  let(:image_name) { "image-from-#{base_name}" }
  let(:image_file) { Dir.pwd + "/image-testfile-#{base_name}" }
  let(:remote_image_name) { "remote-image-from-#{base_name}" }

  it "can export an image to another lxd host" do
    base_driver.images[image_name].export(driver)
    expect(driver.images[image_name].exist?).to be true
  end

  it "can download a remote image" do
    transport.upload_file image_file, "/tmp/imagefile"
    url = "file:///tmp/imagefile" # are file url's supported by lxd?
    driver.images.download url, aliases: [{name: remote_image_name}]
    expect(driver.images[remote_image_name].exist?).to be true
  end
end

shared_examples "it can delete images" do
  let(:image_name) { "image-from-#{name}" }
  let(:image_file) { Dir.pwd + "/image-testfile-#{name}" }
  let(:remote_image_name) { "remote-image-from-#{name}" }

  File.delete image_file

  it "can delete images" do
    driver.images[image_name].delete
    driver.images[remote_image_name].delete
    expect(driver.images[image_name].exist?).to be false
    expect(driver.images[remote_image_name].exist?).to be false
  end
end
