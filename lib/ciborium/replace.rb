# frozen_string_literal: true
# rbs_inline: enabled

# Installs Ciborium::Compat as CBOR, the constant of the cbor gem, in the manner of resolv-replace.
# Require it before anything requires "cbor": with Bundler, after bundler/setup and before
# Bundler.require.

require_relative "compat"

module Ciborium
  module Compat
    # Classes the cbor gem gives to_cbor. URI::Generic is included when URI is loaded.
    CORE_EXT_CLASSES = [
      NilClass,
      TrueClass,
      FalseClass,
      Integer,
      Float,
      String,
      Array,
      Hash,
      Symbol,
      Time,
      Regexp,
      Ciborium::Tagged,
      Ciborium::Simple,
    ].freeze #: Array[Module]

    # Marks the cbor gem's entry point as loaded, so a later require "cbor" cannot replace
    # CBOR. Does nothing when the cbor gem is not installed.
    #
    #: () -> void
    def self.block_cbor_gem
      path = cbor_gem_entry_point
      $LOADED_FEATURES << path if path && !$LOADED_FEATURES.include?(path)
    end

    # The file require "cbor" would load: from the load path once Bundler or RubyGems has
    # activated the cbor gem, or from the gem RubyGems would activate otherwise.
    #
    #: () -> String?
    def self.cbor_gem_entry_point
      type, path = $LOAD_PATH.resolve_feature_path("cbor")
      return path if type == :rb
      return unless defined?(Gem::Specification)

      spec = Gem::Specification.find_by_path("cbor")
      spec&.full_require_paths&.map { |dir| File.join(dir, "cbor.rb") }&.find { |file| File.file?(file) }
    rescue LoadError
      nil
    end

    #: () -> void
    def self.install
      block_cbor_gem
      if Object.const_defined?(:CBOR, false) && !Object.const_get(:CBOR, false).equal?(self)
        warn(
          "ciborium/replace: CBOR was already defined, likely by the cbor gem, and is now replaced. " \
            "Require ciborium/replace before Bundler.require so the cbor gem is never loaded.",
        )
        Object.send(:remove_const, :CBOR)
      end
      Object.const_set(:CBOR, self) unless Object.const_defined?(:CBOR, false)

      classes = CORE_EXT_CLASSES.dup
      classes << ::URI::Generic if defined?(::URI::Generic)
      # prepend rather than include, so these replace to_cbor the cbor gem defined on the class.
      classes.each { |klass| klass.prepend(CoreExt) }
    end
  end
end

Ciborium::Compat.install
