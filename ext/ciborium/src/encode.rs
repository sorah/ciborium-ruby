/// Serializes Ruby objects into CBOR. Recursion is bounded by `max_depth`, which also stops
/// cyclic structures.
pub(crate) struct Encoder<'a> {
    ruby: &'a magnus::Ruby,
    out: Vec<u8>,
    max_depth: usize,
    ctap2: bool,
    fallback: Option<magnus::Value>,
    // Pairs of [class, callable] for allowlisted extensions, consulted in order.
    class_handlers: Option<magnus::RArray>,
    native_module: magnus::RModule,
    tagged_class: magnus::RClass,
    simple_class: magnus::RClass,
    encoded_class: magnus::RClass,
}

impl<'a> Encoder<'a> {
    pub(crate) fn new(
        ruby: &'a magnus::Ruby,
        max_depth: usize,
        flags: u32,
        fallback: Option<magnus::Value>,
        class_handlers: Option<magnus::RArray>,
    ) -> Result<Self, crate::error::Error> {
        use magnus::Module as _;
        let ciborium = ruby
            .class_object()
            .const_get::<_, magnus::RModule>("Ciborium")?;
        Ok(Self {
            ruby,
            out: Vec::new(),
            max_depth,
            ctap2: flags & crate::decode::FLAG_CTAP2 != 0,
            fallback,
            class_handlers,
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
            if self.integer(integer)? {
                return Ok(());
            }
            if self.fallback.is_none() && self.class_handler(value)?.is_none() {
                return Err(crate::error::Error::Encode(
                    "integer is outside -2**64..2**64-1 and the bignum extension is not allowlisted"
                        .to_owned(),
                ));
            }
            return self.extend(value, depth);
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
        self.extend(value, depth)
    }

    /// Encodes what an extension or the fallback returns in place of `value`.
    fn extend(&mut self, value: magnus::Value, depth: usize) -> Result<(), crate::error::Error> {
        use magnus::value::ReprValue as _;
        if let Some(handler) = self.class_handler(value)? {
            let replacement: magnus::Value = handler.funcall("call", (value,))?;
            return self.write(replacement, depth + 1);
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

    fn class_handler(
        &self,
        value: magnus::Value,
    ) -> Result<Option<magnus::Value>, crate::error::Error> {
        use magnus::value::ReprValue as _;
        let Some(handlers) = self.class_handlers else {
            return Ok(None);
        };
        for i in 0..handlers.len() {
            let (module, handler): (magnus::Value, magnus::Value) = handlers.entry(i as isize)?;
            let matched = if let Some(class) = magnus::RClass::from_value(module) {
                value.is_kind_of(class)
            } else if let Some(module) = magnus::RModule::from_value(module) {
                value.is_kind_of(module)
            } else {
                false
            };
            if matched {
                return Ok(Some(handler));
            }
        }
        Ok(None)
    }

    /// Writes an integer in major type 0 or 1. Returns false when it is outside -2**64..2**64-1.
    fn integer(&mut self, integer: magnus::Integer) -> Result<bool, crate::error::Error> {
        use magnus::value::ReprValue as _;
        if let Ok(n) = integer.to_u64() {
            self.push(ciborium_ll::Header::Positive(n))?;
            return Ok(true);
        }
        if let Ok(n) = integer.to_i64() {
            // A negative n is encoded as the argument -1 - n, which is !n in two's complement.
            self.push(ciborium_ll::Header::Negative(!n as u64))?;
            return Ok(true);
        }
        let complement: magnus::Integer = integer.funcall("~", ())?;
        if let Ok(n) = complement.to_u64() {
            self.push(ciborium_ll::Header::Negative(n))?;
            return Ok(true);
        }
        Ok(false)
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
        let start = self.out.len();
        // Where each pair's value begins and ends, for sorting by key afterwards.
        let mut pairs = Vec::new();
        let mut failure = None;
        hash.foreach(|key: magnus::Value, value: magnus::Value| {
            let key_start = self.out.len();
            let result = self.write(key, depth + 1).and_then(|()| {
                let value_start = self.out.len();
                self.write(value, depth + 1)?;
                Ok((key_start, value_start, self.out.len()))
            });
            match result {
                Ok(pair) => {
                    pairs.push(pair);
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
        if pairs.len() != len || hash.len() != len {
            return Err(crate::error::Error::Encode(
                "hash was modified during encoding".to_owned(),
            ));
        }
        if self.ctap2 {
            self.sort_pairs(start, &mut pairs)?;
        }
        Ok(())
    }

    /// Reorders the pairs written since `start` into the ctap2 profile's key order.
    fn sort_pairs(
        &mut self,
        start: usize,
        pairs: &mut [(usize, usize, usize)],
    ) -> Result<(), crate::error::Error> {
        let body = self.out.split_off(start);
        let key = |&(from, to, _): &(usize, usize, usize)| &body[from - start..to - start];
        pairs.sort_by(|a, b| crate::canonical::Ctap2::key_order(key(a), key(b)));
        if pairs.windows(2).any(|w| key(&w[0]) == key(&w[1])) {
            return Err(crate::error::Error::Encode(
                "two map keys have the same encoding".to_owned(),
            ));
        }
        for &(from, _, to) in pairs.iter() {
            self.out.extend_from_slice(&body[from - start..to - start]);
        }
        Ok(())
    }

    fn tagged(&mut self, tagged: magnus::Value, depth: usize) -> Result<(), crate::error::Error> {
        use magnus::value::ReprValue as _;
        if self.ctap2 {
            return Err(crate::error::Error::Encode(
                "tags are not allowed by the ctap2 profile".to_owned(),
            ));
        }
        let tag: u64 = tagged.funcall("tag", ())?;
        let value: magnus::Value = tagged.funcall("value", ())?;
        self.push(ciborium_ll::Header::Tag(tag))?;
        self.write(value, depth + 1)
    }

    /// Splices pre-encoded bytes after checking they hold exactly one well-formed item.
    fn raw(&mut self, bytes: magnus::RString, depth: usize) -> Result<(), crate::error::Error> {
        if self.ctap2 {
            return Err(crate::error::Error::Encode(
                "Encoded cannot be checked against the ctap2 profile".to_owned(),
            ));
        }
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
