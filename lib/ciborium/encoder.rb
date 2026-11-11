# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  # Writes data items one after another into a buffer, for output built in parts.
  class Encoder
    # @rbs @options: EncodeOptions
    # @rbs @buffer: String

    # Options are those of EncodeOptions.build.
    #
    #: (**untyped options) -> void
    def initialize(**options)
      @options = EncodeOptions.build(**options)
      @buffer = "".b
    end

    #: (untyped object) -> self
    def write(object)
      @buffer << Native.encode(object, @options.max_depth, @options.fallback)
      self
    end

    # Writes the head of an array whose length items the caller writes next.
    #
    #: (Integer length) -> self
    def write_array_header(length)
      write_head(4, length)
    end

    # Writes the head of a map whose length key-value pairs the caller writes next.
    #
    #: (Integer length) -> self
    def write_map_header(length)
      write_head(5, length)
    end

    # Writes a tag head; the caller writes the tag content next.
    #
    #: (Integer tag) -> self
    def write_tag(tag)
      write_head(6, tag)
    end

    # A copy of everything written so far.
    #
    #: () -> String
    def bytes
      @buffer.dup
    end

    #: () -> Integer
    def size
      @buffer.bytesize
    end

    #: () -> bool
    def empty?
      @buffer.empty?
    end

    #: () -> self
    def clear
      @buffer.clear
      self
    end

    #: (Integer major, Integer argument) -> self
    private def write_head(major, argument)
      unless argument.is_a?(Integer) && argument.between?(0, Tagged::MAX_TAG)
        raise ArgumentError, "argument must be an Integer in 0..2**64-1, got #{argument.inspect}"
      end

      @buffer << Native.encode_head(major, argument)
      self
    end
  end
end
