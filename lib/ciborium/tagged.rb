# frozen_string_literal: true
# rbs_inline: disabled

module Ciborium
  # A tagged data item (RFC 8949 section 3.4) that no allowlisted extension interprets.
  Tagged = Data.define(:tag, :value)

  class Tagged
    MAX_TAG = 2**64 - 1

    def initialize(tag:, value:)
      unless tag.is_a?(Integer) && tag.between?(0, MAX_TAG)
        raise ArgumentError, "tag must be an Integer between 0 and 2**64-1, got #{tag.inspect}"
      end

      super
    end
  end
end
