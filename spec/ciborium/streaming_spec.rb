# frozen_string_literal: true

RSpec.describe(Ciborium::Decoder) do
  def hex(str) = Vectors.hex(str)

  subject(:decoder) { described_class.new }

  it "decodes items fed byte by byte" do
    input = hex("83010203a161610a9f6161ff")
    items = []
    input.each_char { |byte| decoder.feed(byte).each { |item| items << item } }
    expect(items).to(eq([[1, 2, 3], {"a" => 10}, ["a"]]))
    expect(decoder.buffered_bytes).to(eq(0))
  end

  it "decodes nested containers and indefinite-length strings fed in uneven parts" do
    value = {"a" => [1, {"b" => ["x" * 300, "y".b * 70]}, [[[]]]], "c" => Ciborium::Tagged.new(9, [nil, 2.5])}
    input = Ciborium.encode(value) + hex("7f6161626262ff") + hex("9f5f41014102ffff")
    items = []
    sizes = [1, 7, 2, 64, 3, 500].cycle
    pos = 0
    while pos < input.bytesize
      size = sizes.next
      decoder.feed(input.byteslice(pos, size)).each { |item| items << item }
      pos += size
    end
    expect(items).to(eq([value, "abb", ["\x01\x02".b]]))
  end

  it "rejects a malformed chunk that arrives in a later part" do
    decoder.feed(hex("7f6161"))
    expect(decoder.each.to_a).to(eq([]))
    decoder.feed(hex("4161ff"))
    expect { decoder.read }.to(raise_error(Ciborium::MalformedError, /chunk/))
  end

  it "scans a large item fed in small parts in linear time" do
    input = "\x9f".b + ("\x01".b * 4_000_000) + "\xff".b
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    (0...input.bytesize).step(4096) { |offset| decoder.feed(input.byteslice(offset, 4096)).each { nil } }
    # Rescanning from the start on every part took over ten seconds here.
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to(be < 5)
  end

  it "raises IncompleteError from read without consuming input" do
    decoder.feed(hex("8201"))
    expect { decoder.read }.to(raise_error(Ciborium::IncompleteError))
    decoder.feed(hex("02"))
    expect(decoder.read).to(eq([1, 2]))
  end

  it "returns an Enumerator from each without a block" do
    decoder.feed(hex("0102"))
    expect(decoder.each.first).to(eq(1))
    expect(decoder.read).to(eq(2))
  end

  it "keeps trailing partial data buffered" do
    decoder.feed(hex("01a1"))
    expect(decoder.each.to_a).to(eq([1]))
    expect(decoder.buffered_bytes).to(eq(1))
  end

  it "raises malformed input from each rather than waiting for more" do
    decoder.feed(hex("ff"))
    expect { decoder.each.to_a }.to(raise_error(Ciborium::MalformedError))
  end

  it "skips items, including indefinite-length ones" do
    decoder.feed(hex("9f01829f02ff03ff0405"))
    decoder.skip
    expect(decoder.read).to(eq(4))
    decoder.skip
    expect(decoder.buffered_bytes).to(eq(0))
  end

  it "reads array and map headers" do
    decoder.feed(hex("820102a1616101"))
    expect(decoder.read_array_header).to(eq(2))
    expect(decoder.read).to(eq(1))
    expect(decoder.read).to(eq(2))
    expect(decoder.read_map_header).to(eq(1))
    expect(decoder.read).to(eq("a"))
  end

  it "rejects headers not in their shortest form under the ctap2 profile" do
    decoder = Ciborium::Decoder.new(profile: :ctap2)
    decoder.feed(hex("980101b8010101"))
    expect { decoder.read_array_header }.to(raise_error(Ciborium::MalformedError, /shortest form/))
    decoder.reset.feed(hex("b8010101"))
    expect { decoder.read_map_header }.to(raise_error(Ciborium::MalformedError, /shortest form/))
    decoder.reset.feed(hex("81a10101"))
    expect(decoder.read_array_header).to(eq(1))
    expect(decoder.read_map_header).to(eq(1))
  end

  it "raises UnexpectedTypeError on a header of another type" do
    decoder.feed(hex("9f01ff"))
    expect { decoder.read_array_header }.to(raise_error(Ciborium::UnexpectedTypeError))
    expect { decoder.read_map_header }.to(raise_error(Ciborium::UnexpectedTypeError))
  end

  it "peeks for null with next_nil?" do
    decoder.feed(hex("f601"))
    expect(decoder.next_nil?).to(be(true))
    decoder.skip
    expect(decoder.next_nil?).to(be(false))
    decoder.skip
    expect { decoder.next_nil? }.to(raise_error(Ciborium::IncompleteError))
  end

  it "applies its options to every item" do
    decoder = described_class.new(symbolize_keys: true, max_depth: 1)
    decoder.feed(hex("a1616101"))
    expect(decoder.read).to(eq({a: 1}))
    decoder.feed(hex("8181"))
    expect { decoder.read }.to(raise_error(Ciborium::DepthError))
  end

  it "drops consumed input as it goes" do
    decoder.feed(hex("01") * 10_000)
    expect(decoder.each.count).to(eq(10_000))
    decoder.feed(hex("02"))
    expect(decoder.read).to(eq(2))
  end

  it "drops buffered input on reset" do
    decoder.feed(hex("82"))
    decoder.reset
    decoder.feed(hex("01"))
    expect(decoder.read).to(eq(1))
  end
end

RSpec.describe(Ciborium::Encoder) do
  def hex(str) = Vectors.hex(str)

  subject(:encoder) { described_class.new }

  it "concatenates written items" do
    encoder.write(1).write("a")
    expect(encoder.bytes).to(eq(hex("016161")))
    expect(encoder.size).to(eq(3))
  end

  it "writes array, map and tag heads" do
    encoder.write_array_header(2).write(1).write_map_header(0).write_tag(1).write(0)
    expect(encoder.bytes).to(eq(hex("8201a0c100")))
    expect(Ciborium.decode_sequence(encoder.bytes)).to(eq([[1, {}], Ciborium::Tagged.new(1, 0)]))
  end

  it "rejects head arguments outside 0..2**64-1" do
    expect { encoder.write_array_header(-1) }.to(raise_error(ArgumentError))
    expect { encoder.write_tag(2**64) }.to(raise_error(ArgumentError))
  end

  it "clears its buffer" do
    encoder.write(1).clear
    expect(encoder).to(be_empty)
  end

  it "applies its options to every item" do
    encoder = described_class.new(fallback: ->(_) { 0 })
    expect(encoder.write(Object.new).bytes).to(eq(hex("00")))
  end
end
