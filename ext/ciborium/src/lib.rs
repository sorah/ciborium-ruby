mod canonical;
mod cursor;
mod decode;
mod encode;
mod error;
mod scan;

/// Runs `f` over the bytes of `string` without letting Ruby code mutate or free them meanwhile.
fn with_frozen_bytes<T>(string: magnus::RString, f: impl FnOnce(&[u8]) -> T) -> T {
    // A frozen copy shares the buffer copy-on-write, so later mutation of the caller's string
    // leaves these bytes untouched.
    let frozen = magnus::RString::new_frozen(string);
    // SAFETY: frozen cannot be modified, and it stays on the stack, which the GC scans and pins,
    // until f returns.
    let result = f(unsafe { frozen.as_slice() });
    std::hint::black_box(frozen);
    result
}

/// Decodes the item starting at `offset` and returns it with the offset just past it.
fn decode(
    ruby: &magnus::Ruby,
    input: magnus::RString,
    offset: usize,
    max_depth: usize,
    flags: u32,
    handlers: Option<magnus::RHash>,
) -> Result<(magnus::Value, usize), magnus::Error> {
    crate::with_frozen_bytes(input, |bytes| {
        let mut decoder =
            crate::decode::Decoder::new(ruby, bytes, offset, max_depth, flags, handlers)?;
        let value = decoder.decode()?;
        std::hint::black_box(decoder.pin());
        Ok((value, decoder.pos()))
    })
    .map_err(|error: crate::error::Error| error.into_ruby(ruby))
}

/// Returns the offset just past the item starting at `offset`, or nil when the input ends
/// before it does.
fn scan(
    ruby: &magnus::Ruby,
    input: magnus::RString,
    offset: usize,
    max_depth: usize,
) -> Result<Option<usize>, magnus::Error> {
    crate::with_frozen_bytes(input, |bytes| {
        match crate::scan::Scanner::new(bytes, offset, max_depth).scan() {
            Ok(end) => Ok(Some(end)),
            Err(crate::error::Error::Incomplete) => Ok(None),
            Err(error) => Err(error.into_ruby(ruby)),
        }
    })
}

/// Reads the head at `offset` as `[major type, argument, end offset]`, or nil when the input
/// ends before it does. The argument is nil for indefinite lengths and for major type 7.
fn read_head(
    ruby: &magnus::Ruby,
    input: magnus::RString,
    offset: usize,
) -> Result<Option<(u8, Option<u64>, usize)>, magnus::Error> {
    crate::with_frozen_bytes(input, |bytes| {
        let mut cursor = crate::cursor::Cursor::new(bytes, offset);
        let header = match cursor.head() {
            Ok(header) => header,
            Err(crate::error::Error::Incomplete) => return Ok(None),
            Err(error) => return Err(error.into_ruby(ruby)),
        };
        let (major, argument) = match header {
            ciborium_ll::Header::Positive(n) => (0, Some(n)),
            ciborium_ll::Header::Negative(n) => (1, Some(n)),
            ciborium_ll::Header::Bytes(len) => (2, len.map(|n| n as u64)),
            ciborium_ll::Header::Text(len) => (3, len.map(|n| n as u64)),
            ciborium_ll::Header::Array(len) => (4, len.map(|n| n as u64)),
            ciborium_ll::Header::Map(len) => (5, len.map(|n| n as u64)),
            ciborium_ll::Header::Tag(n) => (6, Some(n)),
            ciborium_ll::Header::Float(_)
            | ciborium_ll::Header::Simple(_)
            | ciborium_ll::Header::Break => (7, None),
        };
        Ok(Some((major, argument, cursor.pos())))
    })
}

/// Encodes a head of major type 4 (array), 5 (map) or 6 (tag) with its argument.
fn encode_head(
    ruby: &magnus::Ruby,
    major: u8,
    argument: u64,
) -> Result<magnus::RString, magnus::Error> {
    let length = || {
        usize::try_from(argument)
            .map_err(|_| magnus::Error::new(ruby.exception_range_error(), "length is too large"))
    };
    let header = match major {
        4 => ciborium_ll::Header::Array(Some(length()?)),
        5 => ciborium_ll::Header::Map(Some(length()?)),
        6 => ciborium_ll::Header::Tag(argument),
        _ => {
            return Err(magnus::Error::new(
                ruby.exception_arg_error(),
                format!("unsupported major type {major}"),
            ));
        }
    };
    let mut out = Vec::new();
    ciborium_ll::Encoder::from(&mut out)
        .push(header)
        .map_err(|error| magnus::Error::new(ruby.exception_io_error(), error.to_string()))?;
    Ok(ruby.str_from_slice(&out))
}

/// Encodes `value` into a binary String.
fn encode(
    ruby: &magnus::Ruby,
    value: magnus::Value,
    max_depth: usize,
    flags: u32,
    fallback: Option<magnus::Value>,
    class_handlers: Option<magnus::RArray>,
) -> Result<magnus::RString, magnus::Error> {
    let run = || -> Result<Vec<u8>, crate::error::Error> {
        let mut encoder =
            crate::encode::Encoder::new(ruby, max_depth, flags, fallback, class_handlers)?;
        encoder.write(value, 0)?;
        Ok(encoder.into_bytes())
    };
    match run() {
        Ok(bytes) => Ok(ruby.str_from_slice(&bytes)),
        Err(error) => Err(error.into_ruby(ruby)),
    }
}

#[magnus::init]
fn init(ruby: &magnus::Ruby) -> Result<(), magnus::Error> {
    use magnus::Module as _;
    let native = ruby.define_module("Ciborium")?.define_module("Native")?;
    native.define_module_function("decode", magnus::function!(crate::decode, 5))?;
    native.define_module_function("encode", magnus::function!(crate::encode, 5))?;
    native.define_module_function("scan", magnus::function!(crate::scan, 3))?;
    native.define_module_function("read_head", magnus::function!(crate::read_head, 2))?;
    native.define_module_function("encode_head", magnus::function!(crate::encode_head, 2))?;
    native.const_set("FLAG_SYMBOLIZE_KEYS", crate::decode::FLAG_SYMBOLIZE_KEYS)?;
    native.const_set("FLAG_LAST_WINS", crate::decode::FLAG_LAST_WINS)?;
    native.const_set("FLAG_CTAP2", crate::decode::FLAG_CTAP2)?;
    Ok(())
}
