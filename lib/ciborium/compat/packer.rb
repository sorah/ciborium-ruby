# frozen_string_literal: true
# rbs_inline: enabled

module Ciborium
  module Compat
    # CBOR::Packer of the cbor gem, writing through Ciborium::Encoder.
    class Packer
      # @rbs @buffer: Buffer
      # @rbs @encoder: Ciborium::Encoder

      attr_reader :buffer #: Buffer

      #: (?untyped io, ?Hash[Symbol, untyped]? options) -> void
      def initialize(io = nil, options = nil)
        @buffer = Buffer.new(io, options)
        @encoder = Ciborium::Encoder.new(**Compat.encode_options)
      end

      #: (untyped object) -> self
      def write(object)
        @encoder.write(object)
        drain
      end

      alias_method :pack, :write

      #: () -> self
      def write_nil
        write(nil)
      end

      #: (Integer length) -> self
      def write_array_header(length)
        @encoder.write_array_header(length)
        drain
      end

      #: (Integer length) -> self
      def write_map_header(length)
        @encoder.write_map_header(length)
        drain
      end

      #: () -> self
      def flush
        @buffer.flush
        self
      end

      #: () -> nil
      def clear
        @buffer.clear
      end

      #: () -> Integer
      def size
        @buffer.size
      end

      #: () -> bool
      def empty?
        @buffer.empty?
      end

      #: (untyped io) -> Integer
      def write_to(io)
        @buffer.write_to(io)
      end

      #: () -> String
      def to_str
        @buffer.to_str
      end

      alias_method :to_s, :to_str

      #: () -> Array[String]
      def to_a
        @buffer.to_a
      end

      #: () -> self
      private def drain
        @buffer << @encoder.bytes
        @encoder.clear
        self
      end
    end
  end
end
