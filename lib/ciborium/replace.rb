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

    # Constants of the cbor gem that CBOR carries.
    CBOR_CONSTANTS = [
      :Packer, :Unpacker, :Buffer, :Tagged, :Simple, :UnpackError, :MalformedFormatError, :StackError, :TypeError,
    ].freeze #: Array[Symbol]

    # Module functions of the cbor gem that CBOR carries.
    CBOR_FUNCTIONS = [:encode, :pack, :dump, :decode, :unpack, :load].freeze #: Array[Symbol]

    # @rbs self.@facade: Module?

    # The frozen module installed as CBOR. It delegates to Compat rather than being Compat, so the
    # cbor gem's extension, should it load anyway, fails on reopening it instead of replacing
    # Compat's methods with its own.
    #
    #: () -> Module
    def self.facade
      @facade ||= begin
        compat = self
        facade = Module.new
        CBOR_CONSTANTS.each { |name| facade.const_set(name, const_get(name)) }
        CBOR_FUNCTIONS.each do |name|
          facade.define_singleton_method(name) { |*args| compat.public_send(name, *args) }
        end
        [Packer, Unpacker, Buffer].each(&:freeze)
        facade.freeze
      end
    end

    # Marks every file of the installed cbor gems that require "cbor" could load as loaded.
    #
    #: () -> void
    def self.block_cbor_gem
      $LOADED_FEATURES.concat(cbor_gem_features - $LOADED_FEATURES)
    end

    # The cbor gem's entry point and extension: as found on the load path, and in every
    # installed version, since RubyGems may activate any of them later.
    #
    #: () -> Array[String]
    def self.cbor_gem_features
      paths = ["cbor", "cbor/cbor"].filter_map do |feature|
        _type, path = $LOAD_PATH.resolve_feature_path(feature)
        path
      rescue LoadError
        nil
      end
      if defined?(Gem::Specification)
        Gem::Specification.find_all_by_name("cbor").each do |spec|
          spec.full_require_paths.each do |dir|
            paths.concat(Dir[File.join(dir, "cbor.rb"), File.join(dir, "cbor", "{,*/}cbor.{so,bundle}")])
          end
        end
      end
      paths.uniq
    end

    #: () -> void
    def self.install
      block_cbor_gem
      if Object.const_defined?(:CBOR, false) && !Object.const_get(:CBOR, false).equal?(facade)
        warn(
          "ciborium/replace: CBOR was already defined, likely by the cbor gem, and is now replaced. " \
            "Require ciborium/replace before Bundler.require so the cbor gem is never loaded.",
        )
        Object.send(:remove_const, :CBOR)
      end
      Object.const_set(:CBOR, facade) unless Object.const_defined?(:CBOR, false)

      classes = CORE_EXT_CLASSES.dup
      classes << ::URI::Generic if defined?(::URI::Generic)
      # prepend rather than include, so these replace to_cbor the cbor gem defined on the class.
      classes.each { |klass| klass.prepend(CoreExt) }
    end
  end
end

Ciborium::Compat.install
