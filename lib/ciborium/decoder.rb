# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  # Decodes data items from input that arrives in parts. Nothing is consumed until a whole item
  # has arrived, so reads that raise IncompleteError can be retried after feeding more.
  class Decoder
    include Enumerable #[untyped]

    # Consumed bytes are dropped from the buffer once they exceed this size.
    COMPACT_THRESHOLD = 4096 #: Integer

    # @rbs @options: DecodeOptions
    # @rbs @buffer: String
    # @rbs @pos: Integer
    # @rbs @scan_state: Native::ScanState

    # Options are those of DecodeOptions.build.
    #
    #: (**untyped options) -> void
    def initialize(**options)
      @options = DecodeOptions.build(**options)
      @buffer = "".b
      @pos = 0
      @scan_state = Native::ScanState.new
    end

    #: (String bytes) -> self
    def feed(bytes)
      compact
      @buffer << bytes.b
      self
    end

    # Decodes the next item. Raises IncompleteError when it has not fully arrived.
    #
    #: () -> untyped
    def read
      item_end
      value, pos = Native.decode(@buffer, @pos, @options.max_depth, @options.flags, @options.handlers)
      advance(pos)
      value
    end

    # Yields each item that has fully arrived, leaving a partial one buffered.
    #
    #: () { (untyped) -> void } -> self
    #: () -> Enumerator[untyped, self]
    def each
      return enum_for(:each) unless block_given?

      yield read while buffered_bytes > 0 && Native.scan(@buffer, @pos, @options.max_depth, @scan_state)
      self
    end

    # Skips the next item without decoding it.
    #
    #: () -> self
    def skip
      advance(item_end)
      self
    end

    # Reads the head of a definite-length array and returns its length, leaving the elements to
    # be read one by one.
    #
    #: () -> Integer
    def read_array_header
      read_container_head(4, "array")
    end

    # Reads the head of a definite-length map and returns its number of pairs.
    #
    #: () -> Integer
    def read_map_header
      read_container_head(5, "map")
    end

    # Whether the next item is null. Consumes nothing.
    #
    #: () -> bool
    def next_nil?
      byte = @buffer.getbyte(@pos)
      raise IncompleteError, "unexpected end of input" unless byte

      byte == 0xf6
    end

    #: () -> Integer
    def buffered_bytes
      @buffer.bytesize - @pos
    end

    # Drops all buffered input.
    #
    #: () -> self
    def reset
      @buffer = "".b
      advance(0)
      self
    end

    #: () -> Integer
    private def item_end
      Native.scan(@buffer, @pos, @options.max_depth, @scan_state) or
        raise IncompleteError, "unexpected end of input"
    end

    # Moves to the next item, whose scan starts afresh.
    #
    #: (Integer pos) -> void
    private def advance(pos)
      @pos = pos
      @scan_state.clear
    end

    #: (Integer major, String name) -> Integer
    private def read_container_head(major, name)
      head = Native.read_head(@buffer, @pos)
      raise IncompleteError, "unexpected end of input" unless head

      actual, length, pos = head
      unless actual == major && length
        raise UnexpectedTypeError, "expected a definite-length #{name}, got major type #{actual}"
      end

      advance(pos)
      length
    end

    # The scan state is relative to @pos, so it stays valid.
    #
    #: () -> void
    private def compact
      return if @pos < COMPACT_THRESHOLD

      @buffer = @buffer.byteslice(@pos..) || "".b
      @pos = 0
    end
  end
end
