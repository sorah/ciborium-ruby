# frozen_string_literal: true

RSpec.describe("the ctap2 profile") do
  def hex(str) = Vectors.hex(str)

  Dir[File.join(__dir__, "../fixtures/webauthn/*.cbor")].each do |path|
    context "with the #{File.basename(path, ".cbor")} attestation object" do
      let(:attestation_object) { File.binread(path) }

      it "decodes and re-encodes it byte for byte" do
        decoded = Ciborium.decode(attestation_object, profile: :ctap2)
        expect(decoded.keys).to(eq(["fmt", "attStmt", "authData"]))
        expect(Ciborium.encode(decoded, profile: :ctap2)).to(eq(attestation_object))
      end

      it "reads the credential public key ahead of extension data" do
        auth_data = Ciborium.decode(attestation_object, profile: :ctap2).fetch("authData")
        credential_id_length = auth_data.byteslice(53, 2).unpack1("n")
        cose_key = auth_data.byteslice((55 + credential_id_length)..)
        extensions = Ciborium.encode({"credProtect" => 1}, profile: :ctap2)

        key, length = Ciborium.decode_prefix(cose_key + extensions, profile: :ctap2)
        expect(key.keys).to(eq([1, 3, -1, -2, -3]))
        expect(length).to(eq(cose_key.bytesize))
        expect(Ciborium.decode(cose_key.byteslice(length..) + extensions, profile: :ctap2)).to(eq({"credProtect" => 1}))
      end
    end
  end

  describe "decoding" do
    it "accepts floats of any width" do
      expect(Ciborium.decode(hex("fb3ff8000000000000"), profile: :ctap2)).to(eq(1.5))
    end

    {
      "a tag" => "c100",
      "an indefinite-length array" => "9f01ff",
      "an indefinite-length map" => "bf0101ff",
      "an indefinite-length string" => "5f4101ff",
      "an integer in a longer form than needed" => "1817",
      "a negative integer in a longer form than needed" => "3900ff",
      "a length in a longer form than needed" => "780161",
      "map keys out of order" => "a2030001ff",
      "a longer text key before a shorter one" => "a262616100616100",
      "a negative key before a positive one" => "a2200001ff",
      "duplicate map keys" => "a201000101",
    }.each do |description, encoded|
      it "rejects #{description}" do
        expect { Ciborium.decode(hex(encoded), profile: :ctap2) }.to(raise_error(Ciborium::MalformedError))
      end
    end

    it "rejects duplicate keys even with duplicate_keys: :last_wins" do
      expect { Ciborium.decode(hex("a201000101"), profile: :ctap2, duplicate_keys: :last_wins) }.to(
        raise_error(Ciborium::MalformedError),
      )
    end

    it "applies to Decoder" do
      decoder = Ciborium::Decoder.new(profile: :ctap2)
      decoder.feed(hex("c100"))
      expect { decoder.read }.to(raise_error(Ciborium::MalformedError))
    end
  end

  describe "encoding" do
    it "sorts map keys by major type, length and bytes" do
      value = {"bb" => 0, -1 => 0, "a" => 0, 10 => 0, 1 => 0, "b".b => 0}
      expect(Ciborium.encode(value, profile: :ctap2)).to(eq(hex("a601000a00200041620061610062626200")))
    end

    it "sorts nested maps" do
      expect(Ciborium.encode([{2 => {"b" => 1, "a" => 2}, 1 => 0}], profile: :ctap2)).to(
        eq(hex("81a2010002a2616102616201")),
      )
    end

    it "rejects keys that encode the same" do
      expect { Ciborium.encode({"a" => 1, a: 2}, profile: :ctap2) }.to(raise_error(Ciborium::EncodeError, /same encoding/))
    end

    it "rejects tags" do
      expect { Ciborium.encode(Ciborium::Tagged.new(1, 0), profile: :ctap2) }.to(raise_error(Ciborium::EncodeError))
      expect { Ciborium::Encoder.new(profile: :ctap2).write_tag(1) }.to(raise_error(Ciborium::EncodeError))
    end

    it "rejects Encoded" do
      expect { Ciborium.encode(Ciborium::Encoded.new(hex("00")), profile: :ctap2) }.to(raise_error(Ciborium::EncodeError))
    end
  end

  it "takes no extensions" do
    expect { Ciborium.decode(hex("00"), profile: :ctap2, extensions: [:bignum]) }.to(raise_error(ArgumentError))
    expect { Ciborium.encode(0, profile: :ctap2, extensions: [:bignum]) }.to(raise_error(ArgumentError))
  end

  it "rejects unknown profiles" do
    expect { Ciborium.decode(hex("00"), profile: :deterministic) }.to(raise_error(ArgumentError))
  end
end
