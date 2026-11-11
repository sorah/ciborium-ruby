# frozen_string_literal: true
# rbs_inline: enabled

require_relative "../ciborium"
require_relative "compat/errors"
require_relative "compat/buffer"
require_relative "compat/packer"
require_relative "compat/unpacker"

module Ciborium
  # The interface of the cbor gem (CBOR), implemented on top of Ciborium. Tag extensions follow
  # Compat.extensions, so a tag that is not allowlisted decodes to Tagged. require
  # "ciborium/replace" to install it as CBOR.
  module Compat
    Tagged = Ciborium::Tagged
    Simple = Ciborium::Simple

    # bignum keeps big Integers transparent, as the cbor gem does, and builds nothing but an
    # Integer from the input.
    DEFAULT_EXTENSIONS = [:bignum].freeze #: Array[extension]

    # @rbs self.@extensions: Array[extension]
    @extensions = DEFAULT_EXTENSIONS

    # The extensions every Compat entry point uses, process-wide.
    #
    #: () -> Array[extension]
    def self.extensions = @extensions

    #: (Array[extension] extensions) -> void
    def self.extensions=(extensions)
      Extensions.resolve(extensions)
      @extensions = extensions.dup.freeze
    end

    # Options for Ciborium::Encoder that reproduce the cbor gem's encoding.
    #
    #: () -> Hash[Symbol, untyped]
    def self.encode_options
      {extensions:, fallback: FALLBACK}
    end

    # Options for Ciborium::Decoder that reproduce the cbor gem's decoding.
    #
    #: () -> Hash[Symbol, untyped]
    def self.decode_options
      {extensions:, duplicate_keys: :last_wins}
    end

    # Encodes object, or writes it to io and returns nil when io is given.
    #
    #: (untyped object, ?untyped io) -> String?
    def self.encode(object, io = nil)
      bytes = Ciborium.encode(object, **encode_options)
      return bytes unless io

      io.write(bytes)
      nil
    end

    # Decodes a single item from a String, or from all that an IO holds.
    #
    # options is {symbolize_keys: true}, or :keys_as_symbols.
    #
    #: (untyped source, ?(Hash[Symbol, untyped] | Symbol)? options) -> untyped
    def self.decode(source, options = nil)
      symbolize_keys = case options
      when nil
        false
      when :keys_as_symbols
        true
      when Hash
        !!options[:symbolize_keys]
      else
        raise ArgumentError, "expected a Hash for options, got #{options.inspect}"
      end
      bytes = source.respond_to?(:read) ? source.read : source
      translate_errors { Ciborium.decode(bytes, **decode_options, symbolize_keys:) }
    end

    class << self
      alias_method :pack, :encode
      alias_method :dump, :encode
      alias_method :unpack, :decode
      alias_method :load, :decode
    end

    # Encodes an object Ciborium cannot represent through its own to_cbor(packer), as the cbor
    # gem does.
    FALLBACK = ->(object) do
      unless object.respond_to?(:to_cbor) && object.method(:to_cbor).owner != CoreExt
        raise EncodeError, "cannot encode an instance of #{object.class}"
      end

      packer = Packer.new
      object.to_cbor(packer)
      Encoded.new(packer.to_s)
    end #: ^(untyped) -> untyped

    # to_cbor for the classes the cbor gem extends. Installed by ciborium/replace.
    module CoreExt
      #: (?untyped packer_or_io) -> untyped
      def to_cbor(packer_or_io = nil)
        return packer_or_io.write(self) if packer_or_io.is_a?(Packer)

        Compat.encode(self, packer_or_io)
      end
    end
  end
end
