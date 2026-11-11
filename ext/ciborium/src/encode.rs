/// Serializes Ruby objects into CBOR. Recursion is bounded by `max_depth`, which also stops
/// cyclic structures.
pub(crate) struct Encoder<'a> {
    ruby: &'a magnus::Ruby,
    out: Vec<u8>,
    max_depth: usize,
    fallback: Option<magnus::Value>,
    native_module: magnus::RModule,
    tagged_class: magnus::RClass,
    simple_class: magnus::RClass,
    encoded_class: magnus::RClass,
}

impl<'a> Encoder<'a> {
    pub(crate) fn new(
        ruby: &'a magnus::Ruby,
        max_depth: usize,
        fallback: Option<magnus::Value>,
    ) -> Result<Self, crate::error::Error> {
        use magnus::Module as _;
        let ciborium = ruby
            .class_object()
            .const_get::<_, magnus::RModule>("Ciborium")?;
        Ok(Self {
            ruby,
            out: Vec::new(),
            max_depth,
            fallback,
            native_module: ciborium.const_get("Native")?,
            tagged_class: ciborium.const_get("Tagged")?,
            simple_class: ciborium.const_get("Simple")?,
            encoded_class: ciborium.const_get("Encoded")?,
        })
    }

    pub(crate) fn into_bytes(self) -> Vec<u8> {
        self.out
    }

    fn encoder(&mut self) -> ciborium_ll::Encoder<&mut Vec<u8>> {
        ciborium_ll::Encoder::from(&mut self.out)
    }

    pub(crate) fn write(
        &mut self,
        value: magnus::Value,
        depth: usize,
    ) -> Result<(), crate::error::Error> {
        use magnus::value::ReprValue as _;
        if depth > self.max_depth {
            return Err(crate::error::Error::Encode(format!(
                "nesting exceeds max_depth ({})",
                self.max_depth
            )));
        }
        if value.is_nil() {
            return self.push(ciborium_ll::Header::Simple(22));
        }
        if magnus::value::Qtrue::from_value(value).is_some() {
            return self.push(ciborium_ll::Header::Simple(21));
        }
        if magnus::value::Qfalse::from_value(value).is_some() {
            return self.push(ciborium_ll::Header::Simple(20));
        }
        if let Some(integer) = magnus::Integer::from_value(value) {
            return self.integer(integer);
        }
        if let Some(float) = magnus::Float::from_value(value) {
            return self.push(ciborium_ll::Header::Float(float.to_f64()));
        }
        if let Some(string) = magnus::RString::from_value(value) {
            return self.string(string);
        }
        if let Some(symbol) = magnus::Symbol::from_value(value) {
            let name: magnus::RString = symbol.funcall("name", ())?;
            return self.string(name);
        }
        if let Some(array) = magnus::RArray::from_value(value) {
            return self.array(array, depth);
        }
        if let Some(hash) = magnus::RHash::from_value(value) {
            return self.hash(hash, depth);
        }
        if value.is_kind_of(self.tagged_class) {
            return self.tagged(value, depth);
        }
        if value.is_kind_of(self.simple_class) {
            let n: u8 = value.funcall("value", ())?;
            if (24..32).contains(&n) {
                return Err(crate::error::Error::Encode(format!(
                    "simple value {n} is reserved"
                )));
            }
            return self.push(ciborium_ll::Header::Simple(n));
        }
        if value.is_kind_of(self.encoded_class) {
            let bytes: magnus::RString = value.funcall("bytes", ())?;
            return self.raw(bytes, depth);
        }
        let Some(fallback) = self.fallback else {
            return Err(crate::error::Error::Encode(format!(
                "cannot encode an instance of {}",
                // SAFETY: the class name is copied into the message before any Ruby code runs.
                unsafe { value.classname() }
            )));
        };
        let replacement: magnus::Value = fallback.funcall("call", (value,))?;
        self.write(replacement, depth + 1)
    }

    fn push(&mut self, header: ciborium_ll::Header) -> Result<(), crate::error::Error> {
        self.encoder()
            .push(header)
            .map_err(|_| crate::error::Error::Encode("failed to write output".to_owned()))
    }

    fn integer(&mut self, integer: magnus::Integer) -> Result<(), crate::error::Error> {
        use magnus::value::ReprValue as _;
        if let Ok(n) = integer.to_u64() {
            return self.push(ciborium_ll::Header::Positive(n));
        }
        if let Ok(n) = integer.to_i64() {
            // A negative n is encoded as the argument -1 - n, which is !n in two's complement.
            return self.push(ciborium_ll::Header::Negative(!n as u64));
        }
        let complement: magnus::Integer = integer.funcall("~", ())?;
        if let Ok(n) = complement.to_u64() {
            return self.push(ciborium_ll::Header::Negative(n));
        }
        Err(crate::error::Error::Encode(
            "integer is outside -2**64..2**64-1".to_owned(),
        ))
    }

    fn string(&mut self, string: magnus::RString) -> Result<(), crate::error::Error> {
        use magnus::encoding::EncodingCapable as _;
        use magnus::value::ReprValue as _;
        let encoding = string.enc_get();
        if encoding == self.ruby.ascii8bit_encindex() {
            // SAFETY: the bytes are copied into the output before any Ruby code runs.
            let bytes = unsafe { string.as_slice() };
            return self
                .encoder()
                .bytes(bytes, None)
                .map_err(|_| crate::error::Error::Encode("failed to write output".to_owned()));
        }
        let utf8 =
            if encoding == self.ruby.utf8_encindex() || encoding == self.ruby.usascii_encindex() {
                string
            } else {
                self.native_module.funcall("transcode", (string,))?
            };
        // SAFETY: the bytes are copied into the output before any Ruby code runs.
        let bytes = unsafe { utf8.as_slice() };
        let Ok(text) = std::str::from_utf8(bytes) else {
            return Err(crate::error::Error::Encode(
                "string is not valid UTF-8".to_owned(),
            ));
        };
        self.encoder()
            .text(text, None)
            .map_err(|_| crate::error::Error::Encode("failed to write output".to_owned()))
    }

    fn array(&mut self, array: magnus::RArray, depth: usize) -> Result<(), crate::error::Error> {
        let len = array.len();
        self.push(ciborium_ll::Header::Array(Some(len)))?;
        // Indexing rather than iterating, because a fallback may change the array meanwhile.
        for i in 0..len {
            let item: magnus::Value = array.entry(i as isize)?;
            self.write(item, depth + 1)?;
        }
        if array.len() != len {
            return Err(crate::error::Error::Encode(
                "array was modified during encoding".to_owned(),
            ));
        }
        Ok(())
    }

    fn hash(&mut self, hash: magnus::RHash, depth: usize) -> Result<(), crate::error::Error> {
        let len = hash.len();
        self.push(ciborium_ll::Header::Map(Some(len)))?;
        let mut failure = None;
        let mut written = 0;
        hash.foreach(|key: magnus::Value, value: magnus::Value| {
            let result = self
                .write(key, depth + 1)
                .and_then(|()| self.write(value, depth + 1));
            match result {
                Ok(()) => {
                    written += 1;
                    Ok(magnus::r_hash::ForEach::Continue)
                }
                Err(error) => {
                    failure = Some(error);
                    Ok(magnus::r_hash::ForEach::Stop)
                }
            }
        })?;
        if let Some(error) = failure {
            return Err(error);
        }
        if written != len || hash.len() != len {
            return Err(crate::error::Error::Encode(
                "hash was modified during encoding".to_owned(),
            ));
        }
        Ok(())
    }

    fn tagged(&mut self, tagged: magnus::Value, depth: usize) -> Result<(), crate::error::Error> {
        use magnus::value::ReprValue as _;
        let tag: u64 = tagged.funcall("tag", ())?;
        let value: magnus::Value = tagged.funcall("value", ())?;
        self.push(ciborium_ll::Header::Tag(tag))?;
        self.write(value, depth + 1)
    }

    /// Splices pre-encoded bytes after checking they hold exactly one well-formed item.
    fn raw(&mut self, bytes: magnus::RString, depth: usize) -> Result<(), crate::error::Error> {
        crate::with_frozen_bytes(bytes, |input| {
            let end = crate::scan::Scanner::new(input, 0, self.max_depth - depth)
                .scan()
                .map_err(|error| {
                    crate::error::Error::Encode(format!(
                        "Encoded does not hold a well-formed data item: {}",
                        error.message()
                    ))
                })?;
            if end != input.len() {
                return Err(crate::error::Error::Encode(
                    "Encoded holds bytes after its data item".to_owned(),
                ));
            }
            self.out.extend_from_slice(input);
            Ok(())
        })
    }
}
