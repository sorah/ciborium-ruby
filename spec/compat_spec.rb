# frozen_string_literal: true

require "stringio"
require "ciborium/compat"

RSpec.describe(Ciborium::Compat) do
  def hex(str) = Vectors.hex(str)

  around do |example|
    extensions = Ciborium::Compat.extensions
    example.run
  ensure
    Ciborium::Compat.extensions = extensions
  end

  it "allowlists only bignum by default" do
    expect(described_class.extensions).to(eq([:bignum]))
    expect(described_class.decode(hex("c249010000000000000000"))).to(eq(2**64))
    expect(described_class.decode(hex("d82363612a62"))).to(eq(Ciborium::Tagged.new(35, "a*b")))
  end

  it "follows extensions set process-wide" do
    described_class.extensions = []
    expect(described_class.decode(hex("c249010000000000000000"))).to(be_a(Ciborium::Tagged))
    expect { described_class.encode(2**64) }.to(raise_error(Ciborium::EncodeError))

    described_class.extensions = [:regexp]
    expect(described_class.decode(hex("d82363612a62"))).to(eq(/a*b/))
  end

  it "rejects invalid extensions" do
    expect { described_class.extensions = [:yaml] }.to(raise_error(ArgumentError))
    expect(described_class.extensions).to(eq([:bignum]))
  end

  describe ".encode" do
    it "writes to an IO and returns nil" do
      io = StringIO.new("".b)
      expect(described_class.encode([1], io)).to(be_nil)
      expect(io.string).to(eq(hex("8101")))
    end

    it "encodes objects through their own to_cbor" do
      point = Struct.new(:x, :y) do
        def to_cbor(packer) = packer.write_array_header(2).write(x).write(y)
      end
      expect(described_class.encode({"p" => point.new(1, 2)})).to(eq(hex("a1617082 0102".delete(" "))))
    end

    it "raises EncodeError on objects without to_cbor" do
      expect { described_class.encode(Object.new) }.to(raise_error(Ciborium::EncodeError))
    end
  end

  describe ".decode" do
    it "reads all of an IO" do
      expect(described_class.decode(StringIO.new(hex("820102")))).to(eq([1, 2]))
    end

    it "symbolizes keys with either form of the option" do
      expect(described_class.decode(hex("a1616101"), symbolize_keys: true)).to(eq({a: 1}))
      expect(described_class.decode(hex("a1616101"), :keys_as_symbols)).to(eq({a: 1}))
    end

    it "keeps the last value of duplicate keys" do
      expect(described_class.decode(hex("a201010102"))).to(eq({1 => 2}))
    end

    it "raises the cbor gem's errors, keeping the Ciborium error as the cause" do
      expect { described_class.decode(hex("8201")) }.to(raise_error(EOFError))
      expect { described_class.decode(hex("ff")) }.to(
        raise_error(Ciborium::Compat::MalformedFormatError) { |e| expect(e.cause).to(be_a(Ciborium::MalformedError)) },
      )
      expect { described_class.decode(("\x81" * 200).b) }.to(raise_error(Ciborium::Compat::StackError))
    end

    it "raises MalformedFormatError when an extension fails" do
      described_class.extensions = [:regexp]
      expect { described_class.decode(hex("d8236128")) }.to(
        raise_error(Ciborium::Compat::MalformedFormatError) { |e| expect(e.cause).to(be_a(Ciborium::ExtensionError)) },
      )
    end
  end

  describe Ciborium::Compat::Unpacker do
    it "reads the first item of an IO with trailing data, as webauthn-ruby does" do
      io = StringIO.new(hex("a201020304") + hex("a16b6372656450726f7465637401"))
      expect(described_class.new(io).each.first).to(eq({1 => 2, 3 => 4}))
    end

    it "reads items from an IO until it ends" do
      expect(described_class.new(StringIO.new(hex("010203"))).each.to_a).to(eq([1, 2, 3]))
    end

    it "takes input through its buffer" do
      unpacker = described_class.new
      unpacker.buffer << hex("8201")
      expect { unpacker.read }.to(raise_error(EOFError))
      unpacker.feed(hex("02"))
      expect(unpacker.read).to(eq([1, 2]))
    end

    it "raises Ciborium::Compat::TypeError from header readers on other types" do
      unpacker = described_class.new.feed(hex("a0"))
      expect { unpacker.read_array_header }.to(raise_error(Ciborium::Compat::TypeError))
    end

    it "takes symbolize_keys as the only argument" do
      expect(described_class.new(symbolize_keys: true).feed(hex("a1616101")).read).to(eq({a: 1}))
    end
  end

  describe Ciborium::Compat::Packer do
    it "writes to its IO on flush" do
      io = StringIO.new("".b)
      packer = described_class.new(io)
      packer.write_array_header(1).write("a")
      expect(io.string).to(be_empty)
      packer.flush
      expect(io.string).to(eq(hex("816161")))
      expect(packer).to(be_empty)
    end
  end
end
