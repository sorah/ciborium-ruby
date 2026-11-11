# frozen_string_literal: true

# Preloaded into rspec in a downstream project, as `bundle exec ruby -r guard.rb -S rspec`, which
# runs it ahead of the project's .rspec. Installs ciborium/replace before the project requires
# "cbor", and fails the run if anything but Ciborium::Compat served CBOR.

require "yaml"
require "rspec/core"

replace_warnings = []
Warning.singleton_class.prepend(
  Module.new do
    define_method(:warn) do |message, **kwargs|
      replace_warnings << message if message.include?("ciborium/replace")
      super(message, **kwargs)
    end
  end,
)

require "ciborium/replace"

RSpec.configure do |config|
  check = lambda do
    raise "CBOR is not Ciborium::Compat" unless CBOR.equal?(Ciborium::Compat)

    native = $LOADED_FEATURES.grep(%r{/cbor/(?:\d+\.\d+/)?cbor\.(?:so|bundle)\z})
    raise "the cbor gem's extension was loaded: #{native.join(", ")}" unless native.empty?
    raise "ciborium/replace warned: #{replace_warnings.join(" ")}" unless replace_warnings.empty?
  end
  config.before(:suite) { check.call }
  config.after(:suite) { check.call }

  # Examples that fail for a documented deviation from the cbor gem. Each runs as pending, so an
  # entry that starts passing fails the run and gets removed.
  suite = ENV.fetch("CIBORIUM_DOWNSTREAM_SUITE")
  expected = YAML.load_file(File.join(__dir__, "expected_failures.yml")).fetch(suite, {})
  config.before do |example|
    reason = expected[example.full_description]
    pending(reason) if reason
  end
end
