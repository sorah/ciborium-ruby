# frozen_string_literal: true
# rbs_inline: enabled

require "time"

module Ciborium
  module Extensions
    # Tag 0 (RFC 3339 text) and tag 1 (seconds since the epoch) as Time.
    class Time
      #: () -> Array[Integer]
      def tags = [0, 1]

      #: () -> Array[Module]
      def classes = [::Time]

      #: (Integer tag, untyped value) -> ::Time
      def decode(tag, value)
        if tag == 0
          raise ArgumentError, "tag 0 content must be text" unless value.is_a?(String)

          return ::Time.iso8601(value)
        end

        unless value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)
          raise ArgumentError, "tag 1 content must be an Integer or a finite Float"
        end

        ::Time.at(value)
      end

      # Whole seconds are written as an Integer, anything finer as a Float.
      #
      #: (::Time object) -> Tagged
      def encode(object)
        Tagged.new(1, object.subsec.zero? ? object.to_i : object.to_f)
      end
    end
  end
end
