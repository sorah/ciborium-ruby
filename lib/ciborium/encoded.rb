# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  # A data item that is already encoded, written out as-is by the encoder. The encoder checks
  # that bytes hold exactly one well-formed item.
  Encoded = Data.define(
    :bytes, #: String
  )
end
