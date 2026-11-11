/// A read position over an input buffer, parsing item heads with ciborium-ll.
pub(crate) struct Cursor<'a> {
    input: &'a [u8],
    pos: usize,
}

impl<'a> Cursor<'a> {
    pub(crate) fn new(input: &'a [u8], pos: usize) -> Self {
        Self { input, pos }
    }

    pub(crate) fn pos(&self) -> usize {
        self.pos
    }

    pub(crate) fn remaining(&self) -> usize {
        self.input.len().saturating_sub(self.pos)
    }

    /// Reads the next item head. ciborium-ll normalises the argument, so checks that depend on
    /// the encoded form look at the raw bytes instead.
    pub(crate) fn head(&mut self) -> Result<ciborium_ll::Header, crate::error::Error> {
        let start = self.pos;
        let rest = self.input.get(start..).unwrap_or_default();
        let mut decoder = ciborium_ll::Decoder::from(rest);
        let header = decoder.pull().map_err(|error| match error {
            ciborium_ll::Error::Io(_) => crate::error::Error::Incomplete,
            ciborium_ll::Error::Syntax(_) => crate::error::Error::malformed(format!(
                "invalid initial byte 0x{:02x} at offset {start}",
                rest[0]
            )),
        })?;
        // RFC 8949 section 3.3: two-byte simple values below 32 are not well-formed.
        if rest[0] == 0xf8 && rest[1] < 32 {
            return Err(crate::error::Error::malformed(format!(
                "invalid simple value encoding at offset {start}"
            )));
        }
        self.pos += decoder.offset();
        Ok(header)
    }

    pub(crate) fn take(&mut self, len: usize) -> Result<&'a [u8], crate::error::Error> {
        if len > self.remaining() {
            return Err(crate::error::Error::Incomplete);
        }
        let bytes = &self.input[self.pos..self.pos + len];
        self.pos += len;
        Ok(bytes)
    }

    /// Reads the body of a byte or text string whose head declared `len`, joining the chunks of
    /// an indefinite-length string. Text is checked to be UTF-8.
    pub(crate) fn string(
        &mut self,
        len: Option<usize>,
        text: bool,
    ) -> Result<std::borrow::Cow<'a, [u8]>, crate::error::Error> {
        let Some(len) = len else {
            return self.indefinite_string(text).map(std::borrow::Cow::Owned);
        };
        let start = self.pos;
        let bytes = self.take(len)?;
        if text {
            crate::cursor::Cursor::check_utf8(bytes, start)?;
        }
        Ok(std::borrow::Cow::Borrowed(bytes))
    }

    fn indefinite_string(&mut self, text: bool) -> Result<Vec<u8>, crate::error::Error> {
        let mut buffer = Vec::new();
        loop {
            let start = self.pos;
            let len = match self.head()? {
                ciborium_ll::Header::Break => return Ok(buffer),
                ciborium_ll::Header::Bytes(Some(len)) if !text => len,
                ciborium_ll::Header::Text(Some(len)) if text => len,
                _ => {
                    return Err(crate::error::Error::malformed(format!(
                        "invalid chunk in indefinite-length string at offset {start}"
                    )));
                }
            };
            let chunk_start = self.pos;
            let chunk = self.take(len)?;
            // RFC 8949 section 3.2.3: each chunk of a text string is valid UTF-8 by itself.
            if text {
                crate::cursor::Cursor::check_utf8(chunk, chunk_start)?;
            }
            buffer.extend_from_slice(chunk);
        }
    }

    fn check_utf8(bytes: &[u8], start: usize) -> Result<(), crate::error::Error> {
        match std::str::from_utf8(bytes) {
            Ok(_) => Ok(()),
            Err(_) => Err(crate::error::Error::malformed(format!(
                "invalid UTF-8 in text string at offset {start}"
            ))),
        }
    }
}
