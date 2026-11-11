# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  DEFAULT_MAX_DEPTH = 128 #: Integer
  MAX_DEPTH_LIMIT = 10_000 #: Integer

  # Decoding options, validated and packed into the arguments the native decoder takes.
  DecodeOptions = Data.define(
    :max_depth, #: Integer
    :flags, #: Integer
    :handlers, #: Hash[Integer, ^(Integer, untyped) -> untyped]?
  )

  class DecodeOptions
    # extensions lists the allowlisted extensions (see Extensions); every other tag decodes to
    # Tagged.
    #
    #: (?extensions: Array[extension], ?symbolize_keys: bool, ?max_depth: Integer, ?duplicate_keys: Symbol) -> DecodeOptions
    def self.build(extensions: [], symbolize_keys: false, max_depth: DEFAULT_MAX_DEPTH, duplicate_keys: :error)
      unless max_depth.is_a?(Integer) && max_depth.between?(1, MAX_DEPTH_LIMIT)
        raise ArgumentError, "max_depth must be an Integer in 1..#{MAX_DEPTH_LIMIT}, got #{max_depth.inspect}"
      end

      flags = 0
      flags |= Native::FLAG_SYMBOLIZE_KEYS if symbolize_keys
      case duplicate_keys
      when :error
        # rejected by default
      when :last_wins
        flags |= Native::FLAG_LAST_WINS
      else
        raise ArgumentError, "duplicate_keys must be :error or :last_wins, got #{duplicate_keys.inspect}"
      end
      new(max_depth:, flags:, handlers: Extensions.tag_handlers(Extensions.resolve(extensions)))
    end
  end
end
