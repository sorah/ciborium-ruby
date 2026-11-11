# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  # Encoding options, validated into the arguments the native encoder takes.
  EncodeOptions = Data.define(
    :max_depth, #: Integer
    :fallback, #: Proc?
    :class_handlers, #: Array[[Module, ^(untyped) -> untyped]]?
  )

  class EncodeOptions
    # extensions lists the allowlisted extensions (see Extensions). fallback is called with each
    # object neither the encoder nor an extension can represent, and returns an object to encode
    # in its place.
    #
    #: (?extensions: Array[extension], ?max_depth: Integer, ?fallback: (^(untyped) -> untyped)?) -> EncodeOptions
    def self.build(extensions: [], max_depth: DEFAULT_MAX_DEPTH, fallback: nil)
      unless max_depth.is_a?(Integer) && max_depth.between?(1, MAX_DEPTH_LIMIT)
        raise ArgumentError, "max_depth must be an Integer in 1..#{MAX_DEPTH_LIMIT}, got #{max_depth.inspect}"
      end

      new(
        max_depth:,
        fallback: fallback && wrap_fallback(fallback),
        class_handlers: Extensions.class_handlers(Extensions.resolve(extensions)),
      )
    end

    #: (^(untyped) -> untyped fallback) -> Proc
    private_class_method def self.wrap_fallback(fallback)
      ->(object) do
        fallback.call(object)
      rescue StandardError
        raise EncodeError, "fallback failed for an instance of #{object.class}"
      end
    end
  end
end
