# frozen_string_literal: true

RSpec.describe(Ciborium) do
  def hex(str) = Vectors.hex(str)

  describe ".decode" do
    (Vectors::PREFERRED + Vectors::NON_PREFERRED).each do |encoded, expected|
      it "decodes #{encoded} to #{expected.inspect}" do
        expect(Ciborium.decode(hex(encoded))).to(eql(expected))
      end
    end

    it "decodes NaN in every width" do
      ["f97e00", "fa7fc00000", "fb7ff8000000000000"].each do |encoded|
        expect(Ciborium.decode(hex(encoded))).to(be_nan)
      end
    end

    it "decodes text as UTF-8 and bytes as binary" do
      expect(Ciborium.decode(hex("6161")).encoding).to(eq(Encoding::UTF_8))
      expect(Ciborium.decode(hex("4161")).encoding).to(eq(Encoding::BINARY))
    end

    it "keeps every tag as Tagged, including the bignum and self-describe tags" do
      expect(Ciborium.decode(hex("c249010000000000000000"))).to(eq(Ciborium::Tagged.new(2, "\x01#{"\x00" * 8}".b)))
      expect(Ciborium.decode(hex("d9d9f700"))).to(eq(Ciborium::Tagged.new(55_799, 0)))
      expect(Ciborium.decode(hex("d82363612a62"))).to(eq(Ciborium::Tagged.new(35, "a*b")))
    end

    it "decodes simple values other than false, true and null as Simple" do
      expect(Ciborium.decode(hex("f7"))).to(eq(Ciborium::UNDEFINED))
      expect(Ciborium.decode(hex("f0"))).to(eq(Ciborium::Simple.new(16)))
      expect(Ciborium.decode(hex("f8ff"))).to(eq(Ciborium::Simple.new(255)))
    end

    it "symbolizes text keys with symbolize_keys" do
      expect(Ciborium.decode(hex("a2616101026162"), symbolize_keys: true)).to(eq({a: 1, 2 => "b"}))
    end

    it "keeps byte string keys as strings with symbolize_keys" do
      expect(Ciborium.decode(hex("a1416101"), symbolize_keys: true)).to(eq({"a".b => 1}))
    end

    it "accepts nesting up to max_depth" do
      expect(Ciborium.decode(hex("818101"), max_depth: 2)).to(eq([[1]]))
    end

    it "raises DepthError beyond max_depth, counting tags" do
      expect { Ciborium.decode(hex("818101"), max_depth: 1) }.to(raise_error(Ciborium::DepthError))
      expect { Ciborium.decode(hex("81c101"), max_depth: 1) }.to(raise_error(Ciborium::DepthError))
    end

    it "raises DepthError rather than overflowing on deep input" do
      expect { Ciborium.decode(("\x81" * 100_000).b) }.to(raise_error(Ciborium::DepthError))
    end

    it "raises MalformedError on duplicate map keys" do
      expect { Ciborium.decode(hex("a201010102")) }.to(raise_error(Ciborium::MalformedError, /duplicate/))
    end

    it "raises MalformedError on duplicate NaN keys, alone or inside a container" do
      expect { Ciborium.decode(hex("a2f97e0001fb7ff800000000000002")) }.to(raise_error(Ciborium::MalformedError, /duplicate/))
      expect { Ciborium.decode(hex("a281f97e000181f97e0002")) }.to(raise_error(Ciborium::MalformedError, /duplicate/))
    end

    it "collapses many NaN keys into one with duplicate_keys: :last_wins" do
      decoded = Ciborium.decode(hex("ba00002710") + (hex("f97e00") + "\x00".b) * 10_000, duplicate_keys: :last_wins)
      expect(decoded.size).to(eq(1))
      expect(decoded.keys.first).to(be_nan)
    end

    it "keeps the last value of a duplicate key with duplicate_keys: :last_wins" do
      expect(Ciborium.decode(hex("a201010102"), duplicate_keys: :last_wins)).to(eq({1 => 2}))
    end

    {
      "invalid UTF-8 in text" => "62fffe",
      "invalid UTF-8 split across chunks" => "7f61c361bcff",
      "a two-byte simple value below 32" => "f810",
      "reserved additional information" => "1c",
      "an indefinite-length integer" => "1f",
      "a nested indefinite-length chunk" => "5f5f4101ffff",
      "a text chunk in a byte string" => "5f6161ff",
      "a break outside an indefinite-length item" => "ff",
      "a break after a map key" => "bf01ff",
      "a break inside a tag" => "9fc1ffff",
      "trailing bytes" => "0101",
    }.each do |description, encoded|
      it "raises MalformedError on #{description}" do
        expect { Ciborium.decode(hex(encoded)) }.to(raise_error(Ciborium::MalformedError))
      end
    end

    {
      "an empty input" => "",
      "a truncated head" => "19",
      "a truncated array" => "8201",
      "a declared length longer than the input" => "5b0000001000000000",
      "an unterminated indefinite-length array" => "9f01",
    }.each do |description, encoded|
      it "raises IncompleteError on #{description}" do
        expect { Ciborium.decode(hex(encoded)) }.to(raise_error(Ciborium::IncompleteError))
      end
    end

    it "rejects invalid options" do
      expect { Ciborium.decode(hex("00"), max_depth: 0) }.to(raise_error(ArgumentError))
      expect { Ciborium.decode(hex("00"), duplicate_keys: :first_wins) }.to(raise_error(ArgumentError))
    end

    it "reserves memory for nested arrays by what the input holds, not what they declare" do
      require "objspace"
      huge_array = "\x9b\x7f\xff\xff\xff\xff\xff\xff\xff".b
      input = (huge_array * 50) + ("\x00".b * 100_000)
      GC.start
      GC.disable
      begin
        before = ObjectSpace.memsize_of_all(Array)
        expect { Ciborium.decode(input) }.to(raise_error(Ciborium::IncompleteError))
        expect(ObjectSpace.memsize_of_all(Array) - before).to(be < 4_000_000)
      ensure
        GC.enable
      end
    end

    it "builds nested containers correctly under GC stress" do
      input = hex("a36161830182026378797aa1616b9f0102ff6162d863826170617161637f61786179ff")
      expected = Ciborium.decode(input)
      GC.stress = true
      begin
        expect(Ciborium.decode(input)).to(eq(expected))
      ensure
        GC.stress = false
      end
    end

    it "keeps open containers and pending keys intact when GC compacts mid-decode" do
      skip "GC compaction is unsupported" unless GC.respond_to?(:verify_compaction_references)

      compacting = Class.new do
        define_method(:tags) { [200] }
        define_method(:classes) { [] }
        define_method(:decode) do |_tag, value|
          GC.verify_compaction_references(expand_heap: true, toward: :empty)
          value
        end
        define_method(:encode) { |object| object }
      end.new
      # An array, a map, and a map awaiting a key's value, each open around the tag.
      expect(Ciborium.decode(hex("8301 02 d8c8 03".delete(" ")), extensions: [compacting])).to(eq([1, 2, 3]))
      expect(Ciborium.decode(hex("a2 6161 01 6162 d8c8 02".delete(" ")), extensions: [compacting]))
        .to(eq({"a" => 1, "b" => 2}))
      expect(Ciborium.decode(hex("a1 6161 82 6162 d8c8 02".delete(" ")), extensions: [compacting]))
        .to(eq({"a" => ["b", 2]}))
    end
  end

  describe ".decode_prefix" do
    it "returns the item and the number of bytes it took" do
      expect(Ciborium.decode_prefix(hex("8201020304"))).to(eq([[1, 2], 3]))
    end
  end

  describe ".decode_sequence" do
    it "decodes every item" do
      expect(Ciborium.decode_sequence(hex("0161618100"))).to(eq([1, "a", [0]]))
    end

    it "decodes an empty sequence" do
      expect(Ciborium.decode_sequence("".b)).to(eq([]))
    end

    it "raises IncompleteError on a truncated last item" do
      expect { Ciborium.decode_sequence(hex("0182")) }.to(raise_error(Ciborium::IncompleteError))
    end
  end

  describe Ciborium::Tagged do
    it "rejects tags outside 0..2**64-1" do
      expect { Ciborium::Tagged.new(-1, 0) }.to(raise_error(RangeError))
      expect { Ciborium::Tagged.new(2**64, 0) }.to(raise_error(RangeError))
      expect { Ciborium::Tagged.new("1", 0) }.to(raise_error(TypeError))
    end
  end

  describe Ciborium::Simple do
    it "rejects reserved and out-of-range values" do
      [24, 31, 256, -1].each do |value|
        expect { Ciborium::Simple.new(value) }.to(raise_error(RangeError))
      end
      expect { Ciborium::Simple.new(nil) }.to(raise_error(TypeError))
    end
  end
end
