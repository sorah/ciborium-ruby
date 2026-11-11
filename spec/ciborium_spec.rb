# frozen_string_literal: true

RSpec.describe(Ciborium) do
  it "has a version number" do
    expect(Ciborium::VERSION).not_to(be_nil)
  end

  it "loads the native extension" do
    expect(Ciborium::Native).to(be_a(Module))
  end
end
