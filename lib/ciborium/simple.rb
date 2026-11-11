# frozen_string_literal: true
# rbs_inline: disabled

module Ciborium
  # A simple value (RFC 8949 section 3.3) other than false, true and null.
  Simple = Data.define(:value)

  class Simple
    def initialize(value:)
      # 24 to 31 are reserved, so no well-formed encoding exists for them.
      unless value.is_a?(Integer) && (value.between?(0, 23) || value.between?(32, 255))
        raise ArgumentError, "simple value must be an Integer in 0..23 or 32..255, got #{value.inspect}"
      end

      super
    end
  end

  UNDEFINED = Simple.new(23)
end
