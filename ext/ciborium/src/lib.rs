mod decode;
mod error;
mod head;

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
) -> Result<(magnus::Value, usize), magnus::Error> {
    crate::with_frozen_bytes(input, |bytes| {
        let mut decoder = crate::decode::Decoder::new(ruby, bytes, offset, max_depth, flags)?;
        let value = decoder.decode()?;
        Ok((value, decoder.pos()))
    })
    .map_err(|error: crate::error::Error| error.into_ruby(ruby))
}

#[magnus::init]
fn init(ruby: &magnus::Ruby) -> Result<(), magnus::Error> {
    use magnus::Module as _;
    let native = ruby.define_module("Ciborium")?.define_module("Native")?;
    native.define_module_function("decode", magnus::function!(crate::decode, 4))?;
    native.const_set("FLAG_SYMBOLIZE_KEYS", crate::decode::FLAG_SYMBOLIZE_KEYS)?;
    native.const_set("FLAG_LAST_WINS", crate::decode::FLAG_LAST_WINS)?;
    Ok(())
}
