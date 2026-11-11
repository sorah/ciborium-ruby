# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe("ciborium/replace") do
  # Each case runs in its own process, since replacing CBOR is process-wide.
  def run_ruby(script, *flags, bundled: true)
    command = [RbConfig.ruby, *flags, "-I", File.expand_path("../lib", __dir__), "-e", script]
    if bundled
      Open3.capture3(*command)
    else
      Bundler.with_unbundled_env { Open3.capture3(*command) }
    end
  end

  it "keeps the cbor gem from loading after it" do
    stdout, stderr, status = run_ruby(<<~RUBY)
      require "ciborium/replace"
      p require("cbor")
      p CBOR.equal?(Ciborium::Compat)
      p $LOADED_FEATURES.grep(%r{/cbor/(?:[\\d.]+/)?cbor\\.(?:so|bundle)\\z}).empty?
    RUBY
    expect(status).to(be_success, stderr)
    expect(stderr).to(be_empty)
    expect(stdout.lines(chomp: true)).to(eq(["false", "true", "true"]))
  end

  it "replaces the cbor gem loaded before it, with a warning" do
    stdout, stderr, status = run_ruby(<<~RUBY)
      require "cbor"
      require "ciborium/replace"
      p CBOR.equal?(Ciborium::Compat)
      p 1.method(:to_cbor).owner
      p CBOR.decode({"a" => 1}.to_cbor) == {"a" => 1}
    RUBY
    expect(status).to(be_success, stderr)
    expect(stderr).to(match(%r{ciborium/replace: CBOR was already defined}))
    expect(stdout.lines(chomp: true)).to(eq(["true", "Ciborium::Compat::CoreExt", "true"]))
  end

  it "blocks the cbor gem without Bundler, through RubyGems" do
    stdout, stderr, status = run_ruby(<<~RUBY, bundled: false)
      require "ciborium/replace"
      p require("cbor")
      p CBOR.equal?(Ciborium::Compat)
    RUBY
    skip("the cbor gem is not installed outside the bundle") if stderr.include?("cannot load such file -- cbor")
    expect(status).to(be_success, stderr)
    expect(stdout.lines(chomp: true)).to(eq(["false", "true"]))
  end

  it "defines CBOR quietly when the cbor gem is not installed" do
    stdout, stderr, status = run_ruby(<<~RUBY, "--disable-gems", bundled: false)
      require "ciborium/replace"
      p CBOR.equal?(Ciborium::Compat)
    RUBY
    expect(status).to(be_success, stderr)
    expect(stderr).to(be_empty)
    expect(stdout).to(eq("true\n"))
  end

  it "gives to_cbor to the classes the cbor gem extends" do
    stdout, stderr, status = run_ruby(<<~RUBY)
      require "uri"
      require "ciborium/replace"
      p [nil, true, false, 1, 1.5, "a", [1], {1 => 2}, :a, Ciborium::Tagged.new(1, 0), Ciborium::UNDEFINED].map { _1.to_cbor.unpack1("H*") }
      p URI("http://example.com").method(:to_cbor).owner
    RUBY
    expect(status).to(be_success, stderr)
    expect(stdout.lines(chomp: true)).to(
      eq(['["f6", "f5", "f4", "01", "f93e00", "6161", "8101", "a10102", "6161", "c100", "f7"]', "Ciborium::Compat::CoreExt"]),
    )
  end
end
