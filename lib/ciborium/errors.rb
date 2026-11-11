# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  class Error < StandardError; end

  class DecodeError < Error; end

  # The input is not well-formed CBOR, or breaks a rule the decoder enforces.
  class MalformedError < DecodeError; end

  # The input ends in the middle of a data item.
  class IncompleteError < DecodeError; end

  # Containers and tags are nested deeper than max_depth.
  class DepthError < DecodeError; end

  # An allowlisted extension failed to decode a tag's content. The cause holds the original error.
  class ExtensionError < DecodeError; end

  # A Decoder head reader found an item of another type.
  class UnexpectedTypeError < DecodeError; end

  class EncodeError < Error; end
end
