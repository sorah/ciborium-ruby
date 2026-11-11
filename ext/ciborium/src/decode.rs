pub(crate) const FLAG_SYMBOLIZE_KEYS: u32 = 1;
pub(crate) const FLAG_LAST_WINS: u32 = 1 << 1;
pub(crate) const FLAG_CTAP2: u32 = 1 << 2;

enum Frame {
    Array {
        array: magnus::RArray,
        remaining: Option<usize>,
    },
    Map {
        hash: magnus::RHash,
        remaining: Option<usize>,
        key: Option<magnus::Value>,
        // Byte ranges of the current and the previous key, for the ctap2 profile's ordering.
        key_start: usize,
        previous_key: Option<(usize, usize)>,
    },
    Tag {
        tag: u64,
    },
}

/// Builds one data item into Ruby objects without recursion, so nesting depth is bounded by
/// `max_depth` rather than by the native stack.
pub(crate) struct Decoder<'a> {
    ruby: &'a magnus::Ruby,
    cursor: crate::cursor::Cursor<'a>,
    max_depth: usize,
    flags: u32,
    // Tag number to a callable taking (tag, content), for allowlisted extensions only.
    handlers: Option<magnus::RHash>,
    stack: Vec<Frame>,
    // Containers held in `stack` live on the Rust heap, which the GC does not scan.
    pin: magnus::value::BoxValue<magnus::RArray>,
    tagged_class: magnus::RClass,
    simple_class: magnus::RClass,
}

impl<'a> Decoder<'a> {
    pub(crate) fn new(
        ruby: &'a magnus::Ruby,
        input: &'a [u8],
        pos: usize,
        max_depth: usize,
        flags: u32,
        handlers: Option<magnus::RHash>,
    ) -> Result<Self, crate::error::Error> {
        use magnus::Module as _;
        let ciborium = ruby
            .class_object()
            .const_get::<_, magnus::RModule>("Ciborium")?;
        Ok(Self {
            ruby,
            cursor: crate::cursor::Cursor::new(input, pos),
            max_depth,
            flags,
            handlers,
            stack: Vec::new(),
            pin: magnus::value::BoxValue::new(ruby.ary_new()),
            tagged_class: ciborium.const_get("Tagged")?,
            simple_class: ciborium.const_get("Simple")?,
        })
    }

    pub(crate) fn pos(&self) -> usize {
        self.cursor.pos()
    }

    /// Decodes the item at the current position and advances past it.
    pub(crate) fn decode(&mut self) -> Result<magnus::Value, crate::error::Error> {
        use magnus::value::ReprValue as _;
        loop {
            let start = self.cursor.pos();
            if let Some(Frame::Map {
                key: None,
                key_start,
                ..
            }) = self.stack.last_mut()
            {
                *key_start = start;
            }
            let header = self.cursor.head()?;
            if self.flags & FLAG_CTAP2 != 0 {
                crate::canonical::Ctap2::check_head(self.cursor.input()[start], &header, start)?;
            }
            let value = match header {
                ciborium_ll::Header::Positive(n) => self.ruby.integer_from_u64(n).as_value(),
                ciborium_ll::Header::Negative(n) => self.negative(n)?,
                ciborium_ll::Header::Float(f) => self.ruby.float_from_f64(f).as_value(),
                ciborium_ll::Header::Simple(n) => self.simple(n)?,
                ciborium_ll::Header::Bytes(len) => self.string(len, false)?,
                ciborium_ll::Header::Text(len) => self.string(len, true)?,
                ciborium_ll::Header::Break => self.close_indefinite(start)?,
                ciborium_ll::Header::Array(len) => {
                    if len == Some(0) {
                        self.ruby.ary_new().as_value()
                    } else {
                        let capacity = len.map_or(0, |n| n.min(self.cursor.remaining()));
                        let array = self.ruby.ary_new_capa(capacity);
                        self.open(Frame::Array {
                            array,
                            remaining: len,
                        })?;
                        continue;
                    }
                }
                ciborium_ll::Header::Map(len) => {
                    if len == Some(0) {
                        self.ruby.hash_new().as_value()
                    } else {
                        let hash = self.ruby.hash_new();
                        self.open(Frame::Map {
                            hash,
                            remaining: len,
                            key: None,
                            key_start: 0,
                            previous_key: None,
                        })?;
                        continue;
                    }
                }
                ciborium_ll::Header::Tag(tag) => {
                    self.open(Frame::Tag { tag })?;
                    continue;
                }
            };
            if let Some(value) = self.complete(value)? {
                return Ok(value);
            }
        }
    }

    fn open(&mut self, frame: Frame) -> Result<(), crate::error::Error> {
        if self.stack.len() >= self.max_depth {
            return Err(crate::error::Error::Depth(self.max_depth));
        }
        match &frame {
            Frame::Array { array, .. } => self.pin.push(*array)?,
            Frame::Map { hash, .. } => self.pin.push(*hash)?,
            Frame::Tag { .. } => {}
        }
        self.stack.push(frame);
        Ok(())
    }

    fn close(&mut self) -> Result<(), crate::error::Error> {
        if let Some(Frame::Array { .. } | Frame::Map { .. }) = self.stack.pop() {
            self.pin.pop::<magnus::Value>()?;
        }
        Ok(())
    }

    /// Hands a finished item to its enclosing container, finishing containers in turn. Returns
    /// the top-level item once there is no container left.
    fn complete(
        &mut self,
        mut value: magnus::Value,
    ) -> Result<Option<magnus::Value>, crate::error::Error> {
        use magnus::value::ReprValue as _;
        loop {
            let finished = match self.stack.last_mut() {
                None => return Ok(Some(value)),
                Some(Frame::Array { array, remaining }) => {
                    array.push(value)?;
                    match remaining {
                        Some(n) => {
                            *n -= 1;
                            if *n > 0 {
                                return Ok(None);
                            }
                            array.as_value()
                        }
                        None => return Ok(None),
                    }
                }
                Some(Frame::Map {
                    hash,
                    remaining,
                    key,
                    key_start,
                    previous_key,
                }) => {
                    let Some(k) = key.take() else {
                        if self.flags & FLAG_CTAP2 != 0 {
                            let current = (*key_start, self.cursor.pos());
                            let input = self.cursor.input();
                            if let Some((from, to)) = *previous_key {
                                let order = crate::canonical::Ctap2::key_order(
                                    &input[from..to],
                                    &input[current.0..current.1],
                                );
                                if order != std::cmp::Ordering::Less {
                                    return Err(crate::error::Error::malformed(format!(
                                        "map key at offset {} is not in canonical order",
                                        current.0
                                    )));
                                }
                            }
                            *previous_key = Some(current);
                        }
                        *key = Some(value);
                        self.pin.push(value)?;
                        return Ok(None);
                    };
                    let size = hash.len();
                    hash.aset(k, value)?;
                    if hash.len() == size && self.flags & FLAG_LAST_WINS == 0 {
                        return Err(crate::error::Error::malformed("duplicate map key"));
                    }
                    let hash = *hash;
                    self.pin.pop::<magnus::Value>()?;
                    match remaining {
                        Some(n) => {
                            *n -= 1;
                            if *n > 0 {
                                return Ok(None);
                            }
                            hash.as_value()
                        }
                        None => return Ok(None),
                    }
                }
                Some(Frame::Tag { tag }) => {
                    let tag = *tag;
                    self.stack.pop();
                    value = self.tag(tag, value)?;
                    continue;
                }
            };
            self.close()?;
            value = finished;
        }
    }

    fn close_indefinite(&mut self, start: usize) -> Result<magnus::Value, crate::error::Error> {
        use magnus::value::ReprValue as _;
        let value = match self.stack.last() {
            Some(Frame::Array {
                array,
                remaining: None,
            }) => array.as_value(),
            Some(Frame::Map {
                hash,
                remaining: None,
                key: None,
                ..
            }) => hash.as_value(),
            _ => {
                return Err(crate::error::Error::malformed(format!(
                    "unexpected break at offset {start}"
                )));
            }
        };
        self.close()?;
        Ok(value)
    }

    fn negative(&self, n: u64) -> Result<magnus::Value, crate::error::Error> {
        use magnus::value::ReprValue as _;
        // The encoded argument n stands for -1 - n.
        Ok(match i64::try_from(n) {
            Ok(n) => self.ruby.integer_from_i64(-1 - n).as_value(),
            Err(_) => self.ruby.integer_from_u64(n).funcall("~", ())?,
        })
    }

    fn simple(&self, n: u8) -> Result<magnus::Value, crate::error::Error> {
        use magnus::IntoValue as _;
        use magnus::value::ReprValue as _;
        Ok(match n {
            20 => false.into_value_with(self.ruby),
            21 => true.into_value_with(self.ruby),
            22 => self.ruby.qnil().as_value(),
            // Data.new maps positional arguments to keywords; rb_class_new_instance would not.
            n => self.simple_class.funcall("new", (n,))?,
        })
    }

    fn tag(&self, tag: u64, value: magnus::Value) -> Result<magnus::Value, crate::error::Error> {
        use magnus::value::ReprValue as _;
        let tag = self.ruby.integer_from_u64(tag);
        if let Some(handler) = self.handlers.and_then(|handlers| handlers.get(tag)) {
            return Ok(handler.funcall("call", (tag, value))?);
        }
        Ok(self.tagged_class.funcall("new", (tag, value))?)
    }

    fn string(
        &mut self,
        len: Option<usize>,
        text: bool,
    ) -> Result<magnus::Value, crate::error::Error> {
        use magnus::value::ReprValue as _;
        let bytes = self.cursor.string(len, text)?;
        if !text {
            return Ok(self.ruby.str_from_slice(&bytes).as_value());
        }
        let string = self.ruby.enc_str_new(&bytes, self.ruby.utf8_encoding());
        if self.flags & FLAG_SYMBOLIZE_KEYS != 0 && self.expects_key() {
            // rb_str_intern creates a dynamic Symbol, which the GC can collect, unlike rb_intern.
            // SAFETY: string is a live String created above, and the GVL is held.
            let symbol =
                unsafe { rb_sys::rb_str_intern(magnus::rb_sys::AsRawValue::as_raw(string)) };
            // SAFETY: rb_str_intern returns a valid Symbol VALUE.
            return Ok(unsafe { magnus::rb_sys::FromRawValue::from_raw(symbol) });
        }
        Ok(string.as_value())
    }

    fn expects_key(&self) -> bool {
        matches!(self.stack.last(), Some(Frame::Map { key: None, .. }))
    }
}
