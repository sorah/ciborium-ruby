# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  module Compat
    # CBOR::Unpacker of the cbor gem, reading through Ciborium::Decoder. Input passes through
    # buffer, which also reads from io when more is needed.
    class Unpacker
      # @rbs @buffer: Buffer
      # @rbs @decoder: Ciborium::Decoder

      attr_reader :buffer #: Buffer

      # options takes symbolize_keys, and the Buffer options.
      #
      #: (?untyped io, ?Hash[Symbol, untyped]? options) -> void
      def initialize(io = nil, options = nil)
        if options.nil? && io.is_a?(Hash)
          options = io
          io = nil
        end
        @buffer = Buffer.new(io, options)
        @decoder = Ciborium::Decoder.new(**Compat.decode_options, symbolize_keys: !!options&.[](:symbolize_keys))
      end

      #: (String data) -> self
      def feed(data)
        @buffer << data
        self
      end

      #: () -> untyped
      def read
        with_input { @decoder.read }
      end

      alias_method :unpack, :read

      #: () -> nil
      def skip
        with_input { @decoder.skip }
        nil
      end

      # Whether the next item is null. Consumes nothing.
      #
      #: () -> bool
      def skip_nil
        with_input { @decoder.next_nil? }
      end

      #: () -> Integer
      def read_array_header
        with_input { @decoder.read_array_header }
      end

      #: () -> Integer
      def read_map_header
        with_input { @decoder.read_map_header }
      end

      # Yields each item until the input runs out, leaving a partial item buffered.
      #
      #: () { (untyped) -> void } -> nil
      #: () -> Enumerator[untyped, nil]
      def each
        return enum_for(:each) unless block_given?

        loop do
          item = begin
            read
          rescue ::EOFError
            break
          end
          yield item
        end
        nil
      end

      #: (String data) { (untyped) -> void } -> nil
      def feed_each(data, &block)
        feed(data)
        each(&block)
      end

      #: () -> nil
      def reset
        @buffer.clear
        @decoder.reset
        nil
      end

      # Runs the block on the decoder, moving more input into it until the block stops raising
      # IncompleteError or the input ends.
      #
      #: [T] () { () -> T } -> T
      private def with_input
        Compat.translate_errors do
          @decoder.feed(@buffer.read_all(@buffer.size)) unless @buffer.empty?
          yield
        rescue IncompleteError
          chunk = @buffer.read(Buffer::DEFAULT_IO_BUFFER_SIZE)
          raise unless chunk

          @decoder.feed(chunk)
          retry
        end
      end
    end
  end
end
