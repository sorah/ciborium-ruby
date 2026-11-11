# Ciborium: CBOR for Ruby without surprises from the input

Ciborium is a [CBOR](https://www.rfc-editor.org/rfc/rfc8949) encoder and decoder for Ruby, backed by a Rust extension built on [ciborium-ll](https://crates.io/crates/ciborium-ll).

It also ships a compatibility layer for the [cbor](https://rubygems.org/gems/cbor) gem. `require "ciborium/replace"` makes `CBOR` refer to Ciborium, so gems written against the cbor gem, such as [webauthn](https://github.com/cedarcode/webauthn-ruby) and [cose](https://github.com/cedarcode/cose-ruby), run on Ciborium unchanged.

## Why

The cbor gem is a fork of msgpack-ruby's C extension with CBOR support added on top, and has not followed the memory-safety fixes msgpack-ruby made since.

Ciborium is a fresh implementation:

- **Memory safety**: parsing and serialization happen in Rust. Nesting is bounded by `max_depth` in both directions, and the decoder needs no recursion.
- **Strict by default**: tags are not interpreted unless an extension is allowlisted, and invalid UTF-8, malformed simple values, duplicate map keys and trailing bytes all raise.
- **CTAP2 canonical form**: `profile: :ctap2` validates and produces the encoding WebAuthn requires.
- **RBS signatures** are shipped in `sig/`.

## Installation

```
bundle add ciborium
```

Ciborium requires Ruby 3.3 or later.

| Platform | Precompiled gem |
|---|---|
| Linux x86_64 and aarch64, glibc 2.34 or later | `x86_64-linux-gnu`, `aarch64-linux-gnu` |
| Linux x86_64 and aarch64, musl | `x86_64-linux-musl`, `aarch64-linux-musl` |
| Linux armv7, glibc 2.31 or later | `arm-linux-gnu` |
| macOS 11 or later on Apple silicon | `arm64-darwin` |
| Windows x64 | `x64-mingw-ucrt` |

The precompiled gems carry the extension for Ruby 3.3, 3.4 and 4.0. Anywhere else the source gem builds the extension, which needs a Rust toolchain and libclang (for [rb-sys](https://github.com/oxidize-rb/rb-sys)).

## Usage

```ruby
require "ciborium"

bytes = Ciborium.encode({"name" => "ciborium", "tags" => [1, 2.5, nil]})
Ciborium.decode(bytes) #=> {"name" => "ciborium", "tags" => [1, 2.5, nil]}

Ciborium.decode("\xd8\x23\x63a*b".b) #=> #<data Ciborium::Tagged tag=35, value="a*b">
```

`decode` raises when bytes follow the item. `decode_prefix` returns the item and the number of bytes it took instead, and `decode_sequence` reads an [RFC 8742](https://www.rfc-editor.org/rfc/rfc8742) sequence:

```ruby
Ciborium.decode_prefix("\x82\x01\x02\xff".b) #=> [[1, 2], 3]
Ciborium.decode_sequence("\x01\x02".b)        #=> [1, 2]
```

### Decoding options

```ruby
Ciborium.decode(bytes,
  extensions: [],           # allowlisted extensions, see below
  symbolize_keys: false,    # text map keys as (garbage-collectable) Symbols
  max_depth: 128,           # nesting limit for arrays, maps and tags
  duplicate_keys: :error,   # or :last_wins
  profile: nil,             # or :ctap2
)
```

### Encoding

| Ruby | CBOR |
|---|---|
| `nil`, `true`, `false` | simple values 22, 21, 20 |
| `Integer` in `-2**64...2**64` | major type 0 or 1, in the shortest form |
| `Float` | the narrowest float that keeps the value exactly |
| `String` in `ASCII-8BIT` | byte string |
| other `String`, `Symbol` | text string, transcoded to UTF-8 |
| `Array`, `Hash` | array, map, in insertion order |
| `Ciborium::Tagged`, `Ciborium::Simple` | tag, simple value |
| `Ciborium::Encoded` | its bytes as-is, after checking they hold one well-formed item |

Anything else raises `Ciborium::EncodeError`, unless an extension encodes it or a `fallback` returns something to encode in its place:

```ruby
Ciborium.encode(Date.today, fallback: ->(date) { date.iso8601 })
```

### Streaming

```ruby
decoder = Ciborium::Decoder.new(symbolize_keys: true)
until io.eof?
  decoder.feed(io.readpartial(4096))
  decoder.each { |item| handle(item) }  # yields only complete items
end

encoder = Ciborium::Encoder.new
encoder.write_array_header(2).write(1).write("two")
encoder.bytes #=> "\x82\x01ctwo"
```

`Decoder` also reads headers (`read_array_header`, `read_map_header`), and offers `skip` and `next_nil?`.

### Errors

| Class | Raised when |
|---|---|
| `Ciborium::MalformedError` | the input is not well-formed, breaks a strictness rule or the profile, or has trailing bytes |
| `Ciborium::IncompleteError` | the input ends inside an item |
| `Ciborium::DepthError` | nesting exceeds `max_depth` |
| `Ciborium::ExtensionError` | an extension failed to decode a tag; the original error is the `cause` |
| `Ciborium::UnexpectedTypeError` | a `Decoder` header reader found another type |
| `Ciborium::EncodeError` | an object cannot be encoded, or an extension or fallback failed |

All of them inherit from `Ciborium::Error`, and the decoding ones also from `Ciborium::DecodeError`.

## Extensions

An extension gives a tag meaning in both directions. Pass the built-in ones by name:

```ruby
Ciborium.decode(bytes, extensions: [:bignum, :time])
Ciborium.encode(Time.now, extensions: [:time])
```

| Name | Tags | Ruby |
|---|---|---|
| `:bignum` | 2, 3 | `Integer` outside `-2**64...2**64` |
| `:time` | 0, 1 | `Time`. It encodes as tag 1, using an Integer for whole seconds and a Float otherwise |
| `:uri` | 32 | `URI::Generic` |
| `:regexp` | 35 | `Regexp` without flags. `Ciborium::Extensions::Regexp.new(timeout: 0.1)` sets a match timeout |

An extension builds Ruby objects from the input, so allowlist only those you trust the input with.

Any object that responds to `tags`, `classes`, `decode(tag, value)` and `encode(object)` is an extension too:

```ruby
class PointExtension
  def tags = [40_000]
  def classes = [Point]
  def decode(_tag, (x, y)) = Point.new(x, y)
  def encode(point) = Ciborium::Tagged.new(40_000, [point.x, point.y])
end

Ciborium.decode(bytes, extensions: [PointExtension.new])
```

## WebAuthn and the CTAP2 profile

WebAuthn encodes everything in the CTAP2 canonical CBOR encoding form ([CTAP 2.2 section 8](https://fidoalliance.org/specs/fido-v2.2-ps-20250714/fido-client-to-authenticator-protocol-v2.2-ps-20250714.html#ctap2-canonical-cbor-encoding-form)). That form uses no tags at all, so WebAuthn data needs no extension. With `profile: :ctap2`, decoding rejects anything outside that form: tags, indefinite lengths, arguments longer than needed, and map keys that are out of order or duplicated. Encoding sorts map keys into canonical order and refuses tags.

```ruby
attestation = Ciborium.decode(attestation_object, profile: :ctap2)

# The credential public key in authenticator data is followed by extension data.
cose_key, length = Ciborium.decode_prefix(credential_public_key_and_rest, profile: :ctap2)
```

## Replacing the cbor gem

`Ciborium::Compat` implements the cbor gem's interface on top of Ciborium:

- `CBOR.encode`, `CBOR.decode` and their `pack`, `dump`, `unpack` and `load` aliases
- `Packer`, `Unpacker` and `Buffer`
- `Tagged`, `Simple`, its error classes, and `to_cbor`

`ciborium/replace` installs it as `CBOR` and marks the cbor gem as loaded, so a later `require "cbor"` does nothing. Keep whatever depends on the cbor gem in the Gemfile, and add ciborium without letting Bundler require it:

```ruby
# Gemfile
gem "webauthn"
gem "ciborium", require: false
```

Then require `ciborium/replace` after Bundler sets up the load path, and before anything requires `cbor`. In a Rails app, that is between these two lines of `config/application.rb`:

```ruby
# config/application.rb
require_relative "boot"
require "rails/all"

require "ciborium/replace"
Bundler.require(*Rails.groups)
```

Outside Rails, put it after `require "bundler/setup"` and before `Bundler.require` or the first `require "webauthn"`. If the cbor gem was loaded first anyway, `ciborium/replace` warns and replaces `CBOR` regardless.

Because callers of the cbor gem cannot pass options, Compat takes its extensions from one process-wide setting. Nothing is allowlisted by default, so big Integers (tags 2 and 3) decode to `Tagged` until `:bignum` is allowlisted:

```ruby
Ciborium::Compat.extensions = [:bignum, :time]
```

The specs of webauthn-ruby and cose-ruby run against Compat in CI with this default, so neither needs any tag extension. The cbor gem's own specs run too, both with no extensions and with every built-in one allowlisted.

### Behaviour of Compat

Compat follows Ciborium's rules rather than reproducing the cbor gem exactly:

- Tags decode to `Tagged` unless allowlisted in `Compat.extensions`, and Integers outside `-2**64...2**64` encode only with `:bignum` allowlisted.
- Input that is not well-formed or breaks Ciborium's strictness rules raises `MalformedFormatError`, as does an extension failure, with the original error as the `cause`.
- Encoding raises `EncodeError` on invalid UTF-8, and on a `Regexp` with flags.
- `Time` encodes subseconds as a Float.
- `Tagged` and `Simple` are immutable `Data`.
- `Unpacker#buffer` holds input that has not yet reached the decoder.

## Development

```
mise install
bin/setup
bundle exec rake compile spec spec:upstream steep
hk check --all
```

The Rust extension lives in `ext/ciborium`. Signatures are written inline with rbs-inline and generated into `sig/generated` by `rake rbs`. That directory is committed, and CI checks it is current.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sorah/ciborium-ruby.

## License

MIT License, see [LICENSE.txt](./LICENSE.txt). Third-party code compiled into the extension, and test fixtures taken from other projects, are listed in [NOTICE.md](./NOTICE.md).
