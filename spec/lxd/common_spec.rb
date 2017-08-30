require "spec_helper"

describe Lxd::Common do
  it "has a version number" do
    expect(Lxd::Common::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(false).to eq(true)
  end
end
