# frozen_string_literal: true

# Runs the specs of the cbor gem (cabo/cbor-ruby), copied unmodified into this directory, against
# Ciborium::Compat. Their own spec_helper is replaced by this file.

require "yaml"
require "ciborium/replace"

# CIBORIUM_UPSTREAM_EXTENSIONS=all runs them with every built-in extension allowlisted.
mode = ENV.fetch("CIBORIUM_UPSTREAM_EXTENSIONS", "default")
Ciborium::Compat.extensions = Ciborium::Extensions::BUILTIN.keys if mode == "all"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = [:should, :expect] }
  config.mock_with(:rspec) { |c| c.syntax = [:should, :expect] }
  config.expose_dsl_globally = true

  # Examples that fail for a documented deviation from the cbor gem. Each runs as pending, so an
  # entry that starts passing fails the run and gets removed.
  expected_failures = YAML.load_file(File.join(__dir__, "expected_failures.yml")).fetch(mode)
  config.before do |example|
    reason = expected_failures[example.full_description]
    pending(reason) if reason
  end
end

class String
  def encode_as_utf8
    encode(Encoding::UTF_8)
  end

  def force_as_utf8
    force_encoding(Encoding::UTF_8)
  end

  def hexbytes(sep = "")
    bytes.map { |x| format("%02x", x) }.join(sep)
  end
end

MessagePack = CBOR
Packer = MessagePack::Packer
Unpacker = MessagePack::Unpacker
Buffer = MessagePack::Buffer
