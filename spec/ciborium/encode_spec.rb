# frozen_string_literal: true

RSpec.describe(Ciborium) do
  def hex(str) = Vectors.hex(str)

  describe ".encode" do
    Vectors::PREFERRED.each do |encoded, value|
      it "encodes #{value.inspect} to #{encoded}" do
        expect(Ciborium.encode(value).unpack1("H*")).to(eq(encoded))
      end
    end

    it "returns a binary String" do
      expect(Ciborium.encode("a").encoding).to(eq(Encoding::BINARY))
    end

    it "encodes NaN as a half-precision float" do
      expect(Ciborium.encode(Float::NAN)).to(eq(hex("f97e00")))
    end

    it "encodes US-ASCII strings and Symbols as text" do
      expect(Ciborium.encode("a".encode(Encoding::US_ASCII))).to(eq(hex("6161")))
      expect(Ciborium.encode(:a)).to(eq(hex("6161")))
    end

    it "transcodes text in other encodings to UTF-8" do
      expect(Ciborium.encode("ü".encode(Encoding::ISO_8859_1))).to(eq(hex("62c3bc")))
    end

    it "encodes subclasses of String, Array and Hash as their base type" do
      string = Class.new(String).new("a")
      array = Class.new(Array).new([1])
      hash = Class.new(Hash).new.merge!(1 => 2)
      expect(Ciborium.encode([string, array, hash])).to(eq(hex("8361618101a10102")))
    end

    it "encodes Tagged, Simple and Encoded" do
      expect(Ciborium.encode(Ciborium::Tagged.new(32, "a"))).to(eq(hex("d8206161")))
      expect(Ciborium.encode([Ciborium::UNDEFINED, Ciborium::Simple.new(255)])).to(eq(hex("82f7f8ff")))
      expect(Ciborium.encode([Ciborium::Encoded.new(hex("820102"))])).to(eq(hex("81820102")))
    end

    it "round-trips through decode" do
      value = {"a" => [1, -2, 3.5, nil], "b" => {1 => "x".b}, "c" => Ciborium::Tagged.new(100, [true])}
      expect(Ciborium.decode(Ciborium.encode(value))).to(eq(value))
    end

    it "raises EncodeError on integers outside -2**64..2**64-1" do
      expect { Ciborium.encode(2**64) }.to(raise_error(Ciborium::EncodeError))
      expect { Ciborium.encode(-(2**64) - 1) }.to(raise_error(Ciborium::EncodeError))
    end

    it "raises EncodeError on invalid UTF-8" do
      expect { Ciborium.encode("\xff".dup.force_encoding(Encoding::UTF_8)) }.to(raise_error(Ciborium::EncodeError))
    end

    it "raises EncodeError with the cause on text that cannot be transcoded" do
      expect { Ciborium.encode("\xff".dup.force_encoding(Encoding::Shift_JIS)) }.to(
        raise_error(Ciborium::EncodeError) { |error| expect(error.cause).to(be_a(EncodingError)) },
      )
    end

    it "raises EncodeError on objects it cannot represent" do
      expect { Ciborium.encode(Object.new) }.to(raise_error(Ciborium::EncodeError, /Object/))
      expect { Ciborium.encode(Time.now) }.to(raise_error(Ciborium::EncodeError, /Time/))
    end

    it "raises EncodeError on cyclic structures" do
      array = []
      array << array
      expect { Ciborium.encode(array) }.to(raise_error(Ciborium::EncodeError, /max_depth/))
    end

    it "raises EncodeError beyond max_depth" do
      expect(Ciborium.encode([[1]], max_depth: 2)).to(eq(hex("818101")))
      expect { Ciborium.encode([[1]], max_depth: 1) }.to(raise_error(Ciborium::EncodeError))
    end

    it "raises EncodeError on an Encoded without exactly one well-formed item" do
      expect { Ciborium.encode(Ciborium::Encoded.new(hex("8201"))) }.to(raise_error(Ciborium::EncodeError))
      expect { Ciborium.encode(Ciborium::Encoded.new(hex("0101"))) }.to(raise_error(Ciborium::EncodeError))
      expect { Ciborium.encode(Ciborium::Encoded.new(hex("62fffe"))) }.to(raise_error(Ciborium::EncodeError))
    end

    describe "fallback" do
      it "encodes what fallback returns in place of the object" do
        fallback = ->(time) { Ciborium::Tagged.new(1, time.to_i) }
        expect(Ciborium.encode([Time.at(0)], fallback:)).to(eq(hex("81c100")))
      end

      it "wraps errors raised by fallback in EncodeError" do
        expect { Ciborium.encode(Object.new, fallback: ->(_) { raise "boom" }) }.to(
          raise_error(Ciborium::EncodeError) { |error| expect(error.cause.message).to(eq("boom")) },
        )
      end

      it "raises EncodeError when fallback keeps returning unencodable objects" do
        expect { Ciborium.encode(Object.new, fallback: ->(object) { object }) }.to(raise_error(Ciborium::EncodeError))
      end

      it "raises EncodeError when fallback modifies an array being encoded" do
        array = [Object.new, 1]
        fallback = ->(_) { array.pop && 0 }
        expect { Ciborium.encode(array, fallback:) }.to(raise_error(Ciborium::EncodeError, /modified/))
      end

      it "raises EncodeError when fallback deletes from a hash being encoded" do
        hash = {a: Object.new, b: 1}
        fallback = ->(_) { hash.delete(:b) && 0 }
        expect { Ciborium.encode(hash, fallback:) }.to(raise_error(Ciborium::EncodeError, /modified/))
      end
    end
  end
end
