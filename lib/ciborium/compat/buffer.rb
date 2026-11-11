# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  module Compat
    # A byte queue in front of an optional IO, as CBOR::Buffer of the cbor gem: reads refill from
    # the IO when the queue runs dry, and writes go out to it once the queue fills.
    class Buffer
      DEFAULT_IO_BUFFER_SIZE = 32 * 1024 #: Integer

      # @rbs @io: untyped
      # @rbs @io_buffer_size: Integer
      # @rbs @data: String
      # @rbs @pos: Integer

      attr_reader :io #: untyped

      # The cbor gem's read_reference_threshold and write_reference_threshold tune its chunk
      # sharing, which this buffer does not do, so they are accepted and ignored.
      #
      #: (?untyped io, ?Hash[Symbol, untyped]? options) -> void
      def initialize(io = nil, options = nil)
        if options.nil? && io.is_a?(Hash)
          options = io
          io = nil
        end
        @io = io
        @io_buffer_size = Integer(options ? options.fetch(:io_buffer_size, DEFAULT_IO_BUFFER_SIZE) : DEFAULT_IO_BUFFER_SIZE)
        @data = "".b
        @pos = 0
      end

      #: () -> nil
      def clear
        @data = "".b
        @pos = 0
        nil
      end

      #: () -> Integer
      def size
        @data.bytesize - @pos
      end

      #: () -> bool
      def empty?
        size.zero?
      end

      #: (String data) -> Integer
      def write(data)
        @data << data.b
        flush if @io && size >= @io_buffer_size
        data.bytesize
      end

      #: (String data) -> self
      def <<(data)
        write(data)
        self
      end

      # Consumes up to n bytes, or everything without n, refilling from the IO until it ends.
      # Returns nil when n is positive and nothing is left.
      #
      #: (?Integer? n, ?String? out) -> String?
      def read(n = nil, out = nil)
        return read_all(nil, out) if n.nil?
        return replace(out, "".b) if n.zero?

        fill(n)
        return if empty?

        replace(out, take(n))
      end

      # Consumes exactly n bytes, or everything without n. Raises EOFError, consuming nothing,
      # when fewer than n bytes are left.
      #
      #: (?Integer? n, ?String? out) -> String
      def read_all(n = nil, out = nil)
        if n.nil?
          fill(nil)
          return replace(out, take(size))
        end
        return replace(out, "".b) if n.zero?

        fill(n)
        raise ::EOFError, "end of buffer reached" if size < n

        replace(out, take(n))
      end

      # Consumes up to n bytes and returns how many it consumed.
      #
      #: (Integer n) -> Integer
      def skip(n)
        fill(n)
        take(n).bytesize
      end

      # Consumes exactly n bytes, or raises EOFError consuming nothing.
      #
      #: (Integer n) -> self
      def skip_all(n)
        fill(n)
        raise ::EOFError, "end of buffer reached" if size < n

        take(n)
        self
      end

      #: () -> String
      def to_str
        @data.byteslice(@pos..) || "".b
      end

      alias_method :to_s, :to_str

      #: () -> Array[String]
      def to_a
        [to_str]
      end

      # Writes the queued bytes to the IO, if there is one.
      #
      #: () -> self
      def flush
        write_to(@io) if @io
        self
      end

      #: () -> nil
      def close
        @io&.close
        nil
      end

      # Writes the queued bytes to io and consumes them.
      #
      #: (untyped io) -> Integer
      def write_to(io)
        data = take(size)
        io.write(data)
        data.bytesize
      end

      #: (Integer? n) -> void
      private def fill(n)
        return unless @io

        while n.nil? || size < n
          chunk = read_io
          break unless chunk

          @data << chunk.b
        end
      end

      #: () -> String?
      private def read_io
        if @io.respond_to?(:readpartial)
          @io.readpartial(@io_buffer_size)
        else
          @io.read(@io_buffer_size)
        end
      rescue ::EOFError
        nil
      end

      #: (Integer n) -> String
      private def take(n)
        data = @data.byteslice(@pos, n) || "".b
        @pos += data.bytesize
        if @pos == @data.bytesize
          @data = "".b
          @pos = 0
        end
        data
      end

      #: (String? out, String data) -> String
      private def replace(out, data)
        return data unless out

        out.replace(data)
      end
    end
  end
end
