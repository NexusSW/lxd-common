require "support/shared_examples"

shared_context "Nesting" do
  it "can set up a nested LXD" do
    expect { transport.execute('bash -c "while ! [ -a /var/lib/lxd/unix.socket ]; do sleep 1; done; lxd init --auto"').error! }.not_to raise_error
  end
  describe "Nested CLI Driver" do
    subject(:name) { "nested-" + base_name }
    subject(:driver) { NexusSW::LXD::Driver::CLI.new(base_transport.tap { |t| t.user "ubuntu" }) }
    include_context "it can transfer images"
    include_context "it can create containers"
    include_context "Transport Functions"
    include_context "it can teardown a container"
  end
end

shared_context "Driver Test" do |enable_nesting_tests = false|
  include_examples "it can create containers"
  it "waits upon startup" do
    ip = driver.wait_for(name, :ip)
    driver.wait_for(name, :cloud_init)
    expect(ip).not_to eq nil
    expect(ip).not_to be_empty
    expect(ip.is_a?(String)).to be true
  end
  include_examples "it can manage images"
  context "Transport" do
    include_examples "Transport Functions"
    include_context "Nesting" if enable_nesting_tests
  end
  include_context "it can delete images"
  it_behaves_like "it can teardown a container"
end
