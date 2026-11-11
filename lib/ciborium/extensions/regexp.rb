# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  module Extensions
    # Tag 35 as Regexp. Compiling a pattern from untrusted input risks ReDoS, so pass a timeout
    # unless Regexp.timeout is set.
    class Regexp
      FLAGS = ::Regexp::IGNORECASE | ::Regexp::EXTENDED | ::Regexp::MULTILINE #: Integer

      # @rbs @timeout: Float?

      #: (?timeout: Float?) -> void
      def initialize(timeout: nil)
        @timeout = timeout
      end

      #: () -> Array[Integer]
      def tags = [35]

      #: () -> Array[Module]
      def classes = [::Regexp]

      #: (Integer tag, untyped value) -> ::Regexp
      def decode(tag, value)
        raise ArgumentError, "tag #{tag} content must be text" unless value.is_a?(String)

        ::Regexp.new(value, timeout: @timeout)
      end

      # Tag 35 has no place for flags, so a Regexp with any is refused rather than changed.
      #
      #: (::Regexp object) -> Tagged
      def encode(object)
        raise ArgumentError, "cannot encode #{object.inspect}: tag 35 carries no flags" if object.options & FLAGS != 0

        Tagged.new(35, object.source)
      end
    end
  end
end
