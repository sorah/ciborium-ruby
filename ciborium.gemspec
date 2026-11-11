# frozen_string_literal: true

require_relative "lib/ciborium/version"

Gem::Specification.new do |spec|
  spec.name = "ciborium"
  spec.version = Ciborium::VERSION
  spec.authors = ["Sorah Fukumori"]
  spec.email = ["sorah@ivry.jp"]

  spec.summary = "Memory-safe CBOR (RFC 8949) encoder and decoder with allowlisted tag extensions"
  spec.description = "A CBOR implementation backed by a Rust extension. Tags carry no meaning unless an " \
    "extension for them is allowlisted. Ships a compatibility layer for the cbor gem's interface."
  spec.homepage = "https://github.com/sorah/ciborium-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  dev_only = %w[
    bin/
    spec/
    sig-stub/
    script/
    rakelib/
    .github/
    tmp/
    pkg/
    mise.lock
    Gemfile
    .gitignore
    .rspec
    .rubocop.yml
    Steepfile
    rbs_collection
    hk.pkl
    mise.toml
  ]
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      f == gemspec || f.start_with?(*dev_only)
    end
  end
  spec.require_paths = ["lib"]
end
