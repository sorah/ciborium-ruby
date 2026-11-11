# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  module Extensions
    # Tags 2 and 3 (RFC 8949 section 3.4.3): integers outside -2**64..2**64-1 as byte strings.
    class BigInteger
      #: () -> Array[Integer]
      def tags = [2, 3]

      #: () -> Array[Module]
      def classes = [Integer]

      #: (Integer tag, untyped value) -> Integer
      def decode(tag, value)
        unless value.is_a?(String) && value.encoding == Encoding::BINARY
          raise ArgumentError, "tag #{tag} content must be a byte string"
        end

        # unpack1 is typed as any directive's result; "H*" always yields a String.
        hex = value.unpack1("H*") #: String
        n = hex.empty? ? 0 : hex.to_i(16)
        tag == 2 ? n : -1 - n
      end

      #: (Integer object) -> Tagged
      def encode(object)
        tag, n = object.negative? ? [3, -1 - object] : [2, object]
        hex = n.to_s(16)
        hex = "0#{hex}" if hex.size.odd?
        Tagged.new(tag, [hex].pack("H*"))
      end
    end
  end
end
