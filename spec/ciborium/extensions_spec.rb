# frozen_string_literal: true

require "time"
require "uri"

RSpec.describe(Ciborium::Extensions) do
  def hex(str) = Vectors.hex(str)

  context "without extensions" do
    {
      "a bignum" => "c249010000000000000000",
      "a date-time string" => "c074323031332d30332d32315432303a30343a30305a",
      "an epoch time" => "c11a514b67b0",
      "a URI" => "d82076687474703a2f2f7777772e6578616d706c652e636f6d",
      "a regular expression" => "d82363612a62",
    }.each do |description, encoded|
      it "decodes #{description} to Tagged" do
        expect(Ciborium.decode(hex(encoded))).to(be_a(Ciborium::Tagged))
      end
    end

    it "refuses to encode Time, URI and Regexp" do
      [Time.at(0), URI("http://example.com"), /a/].each do |object|
        expect { Ciborium.encode(object) }.to(raise_error(Ciborium::EncodeError))
      end
    end

    it "refuses to encode integers outside -2**64..2**64-1" do
      expect { Ciborium.encode(2**64) }.to(raise_error(Ciborium::EncodeError, /bignum/))
    end
  end

  describe ":bignum" do
    it "decodes RFC 8949 Appendix A bignums" do
      expect(Ciborium.decode(hex("c249010000000000000000"), extensions: [:bignum])).to(eq(2**64))
      expect(Ciborium.decode(hex("c349010000000000000000"), extensions: [:bignum])).to(eq(-(2**64) - 1))
    end

    it "decodes an empty byte string and leading zeros" do
      expect(Ciborium.decode(hex("c240"), extensions: [:bignum])).to(eq(0))
      expect(Ciborium.decode(hex("c243000001"), extensions: [:bignum])).to(eq(1))
    end

    it "encodes only integers outside -2**64..2**64-1 as bignums" do
      expect(Ciborium.encode(2**64, extensions: [:bignum])).to(eq(hex("c249010000000000000000")))
      expect(Ciborium.encode(-(2**64) - 1, extensions: [:bignum])).to(eq(hex("c349010000000000000000")))
      expect(Ciborium.encode(2**64 - 1, extensions: [:bignum])).to(eq(hex("1bffffffffffffffff")))
    end

    it "round-trips large integers" do
      n = 256**3000 + 4711
      expect(Ciborium.decode(Ciborium.encode([n, -n], extensions: [:bignum]), extensions: [:bignum])).to(eq([n, -n]))
    end

    it "raises ExtensionError on content other than a byte string" do
      expect { Ciborium.decode(hex("c26161"), extensions: [:bignum]) }.to(
        raise_error(Ciborium::ExtensionError) { |error| expect(error.cause).to(be_a(ArgumentError)) },
      )
    end
  end

  describe ":time" do
    it "decodes tag 0 and tag 1" do
      expect(Ciborium.decode(hex("c074323031332d30332d32315432303a30343a30305a"), extensions: [:time])).to(
        eq(Time.utc(2013, 3, 21, 20, 4, 0)),
      )
      expect(Ciborium.decode(hex("c11a514b67b0"), extensions: [:time])).to(eq(Time.at(1_363_896_240)))
      expect(Ciborium.decode(hex("c1fb41d452d9ec200000"), extensions: [:time])).to(eq(Time.at(1_363_896_240.5)))
    end

    it "encodes whole seconds as an Integer and finer times as a Float" do
      expect(Ciborium.encode(Time.at(1_363_896_240), extensions: [:time])).to(eq(hex("c11a514b67b0")))
      expect(Ciborium.encode(Time.at(1_363_896_240.5), extensions: [:time])).to(eq(hex("c1fb41d452d9ec200000")))
    end

    it "raises ExtensionError on content of the wrong type" do
      ["c16161", "c1f97e00", "c001", "c06161"].each do |encoded|
        expect { Ciborium.decode(hex(encoded), extensions: [:time]) }.to(raise_error(Ciborium::ExtensionError))
      end
    end
  end

  describe ":uri" do
    it "round-trips URIs" do
      encoded = hex("d82076687474703a2f2f7777772e6578616d706c652e636f6d")
      expect(Ciborium.decode(encoded, extensions: [:uri])).to(eq(URI("http://www.example.com")))
      expect(Ciborium.encode(URI("http://www.example.com"), extensions: [:uri])).to(eq(encoded))
    end

    it "raises ExtensionError on an invalid URI" do
      expect { Ciborium.decode(hex("d820623a3a"), extensions: [:uri]) }.to(raise_error(Ciborium::ExtensionError))
    end
  end

  describe ":regexp" do
    it "round-trips patterns without flags" do
      expect(Ciborium.decode(hex("d82363612a62"), extensions: [:regexp])).to(eq(/a*b/))
      expect(Ciborium.encode(/a*b/, extensions: [:regexp])).to(eq(hex("d82363612a62")))
    end

    it "refuses to encode a pattern with flags" do
      expect { Ciborium.encode(/a/i, extensions: [:regexp]) }.to(raise_error(Ciborium::EncodeError))
    end

    it "raises ExtensionError on an invalid pattern" do
      expect { Ciborium.decode(hex("d8236128"), extensions: [:regexp]) }.to(raise_error(Ciborium::ExtensionError))
    end

    it "applies a match timeout" do
      regexp = Ciborium.decode(hex("d82361 61".delete(" ")), extensions: [Ciborium::Extensions::Regexp.new(timeout: 0.5)])
      expect(regexp.timeout).to(eq(0.5))
    end
  end

  describe "custom extensions" do
    let(:point) { Struct.new(:x, :y) }
    let(:extension) do
      klass = point
      Class.new do
        define_method(:tags) { [40_000] }
        define_method(:classes) { [klass] }
        define_method(:decode) { |_tag, (x, y)| klass.new(x, y) }
        define_method(:encode) { |p| Ciborium::Tagged.new(40_000, [p.x, p.y]) }
      end.new
    end

    it "round-trips through an extension object" do
      encoded = Ciborium.encode([point.new(1, 2)], extensions: [extension])
      expect(Ciborium.decode(encoded, extensions: [extension])).to(eq([point.new(1, 2)]))
    end

    it "uses extensions given to Encoder and Decoder" do
      encoder = Ciborium::Encoder.new(extensions: [:bignum])
      decoder = Ciborium::Decoder.new(extensions: [:bignum])
      decoder.feed(encoder.write(2**70).bytes)
      expect(decoder.read).to(eq(2**70))
    end

    it "rejects objects that are not extensions and unknown names" do
      expect { Ciborium.decode(hex("00"), extensions: [Object.new]) }.to(raise_error(ArgumentError))
      expect { Ciborium.decode(hex("00"), extensions: [:yaml]) }.to(raise_error(ArgumentError))
    end

    it "rejects two extensions for one tag" do
      expect { Ciborium.decode(hex("00"), extensions: [:time, :time]) }.to(raise_error(ArgumentError))
    end
  end
end
