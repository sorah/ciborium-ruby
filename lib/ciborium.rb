# frozen_string_literal: true
# rbs_inline: enabled

require_relative "ciborium/version"
require_relative "ciborium/errors"
require_relative "ciborium/tagged"
require_relative "ciborium/simple"
require_relative "ciborium/encoded"
require_relative "ciborium/native"
require_relative "ciborium/extensions"
require_relative "ciborium/decode_options"
require_relative "ciborium/encode_options"
require_relative "ciborium/encoder"
require_relative "ciborium/decoder"

# A CBOR (RFC 8949) encoder and decoder. Tags carry no meaning unless an extension for them is
# allowlisted.
module Ciborium
  # Encodes object into a binary String.
  #
  # Options are those of EncodeOptions.build.
  #
  #: (untyped object, **untyped options) -> String
  def self.encode(object, **options)
    opts = EncodeOptions.build(**options)
    Native.encode(object, opts.max_depth, opts.flags, opts.fallback, opts.class_handlers)
  end

  # Decodes a single data item. Raises MalformedError when bytes follow it.
  #
  # Options are those of DecodeOptions.build.
  #
  #: (String bytes, **untyped options) -> untyped
  def self.decode(bytes, **options)
    value, pos = decode_prefix(bytes, **options)
    unless pos == bytes.bytesize
      raise MalformedError, "#{bytes.bytesize - pos} bytes follow the decoded item"
    end

    value
  end

  # Decodes the data item at the start of bytes and returns it with the number of bytes it took,
  # leaving whatever follows unread.
  #
  #: (String bytes, **untyped options) -> [untyped, Integer]
  def self.decode_prefix(bytes, **options)
    opts = DecodeOptions.build(**options)
    Native.decode(bytes, 0, opts.max_depth, opts.flags, opts.handlers)
  end

  # Decodes a CBOR sequence (RFC 8742), a concatenation of zero or more data items.
  #
  #: (String bytes, **untyped options) -> Array[untyped]
  def self.decode_sequence(bytes, **options)
    opts = DecodeOptions.build(**options)
    items = [] #: Array[untyped]
    pos = 0
    while pos < bytes.bytesize
      item, pos = Native.decode(bytes, pos, opts.max_depth, opts.flags, opts.handlers)
      items << item
    end
    items
  end
end
