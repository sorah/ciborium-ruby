# frozen_string_literal: true
# rbs_inline: enabled

require "uri"

module Ciborium
  module Extensions
    # Tag 32 (RFC 8949 section 3.4.5.3) as URI.
    class URI
      #: () -> Array[Integer]
      def tags = [32]

      #: () -> Array[Module]
      def classes = [::URI::Generic]

      #: (Integer tag, untyped value) -> ::URI::Generic
      def decode(tag, value)
        raise ArgumentError, "tag #{tag} content must be text" unless value.is_a?(String)

        ::URI.parse(value)
      end

      #: (::URI::Generic object) -> Tagged
      def encode(object)
        Tagged.new(32, object.to_s)
      end
    end
  end
end
