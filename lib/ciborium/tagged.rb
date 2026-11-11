# frozen_string_literal: true
# rbs_inline: disabled

module Ciborium
  # A tagged data item (RFC 8949 section 3.4) that no allowlisted extension interprets.
  Tagged = Data.define(:tag, :value)

  class Tagged
    MAX_TAG = 2**64 - 1

    def initialize(tag:, value:)
      raise ::TypeError, "tag must be an Integer, got #{tag.inspect}" unless tag.is_a?(Integer)
      raise ::RangeError, "tag must be between 0 and 2**64-1, got #{tag}" unless tag.between?(0, MAX_TAG)

      super
    end
  end
end
