/// One item head: the initial byte plus its argument, as parsed by ciborium-ll.
pub(crate) struct Head {
    pub(crate) header: ciborium_ll::Header,
    pub(crate) len: usize,
}

impl Head {
    /// Parses the head at `input[pos..]`. ciborium-ll normalises the argument, so checks that
    /// depend on the encoded form look at the raw bytes instead.
    pub(crate) fn parse(input: &[u8], pos: usize) -> Result<Self, crate::error::Error> {
        let rest = input.get(pos..).unwrap_or_default();
        let mut decoder = ciborium_ll::Decoder::from(rest);
        let header = decoder.pull().map_err(|error| match error {
            ciborium_ll::Error::Io(_) => crate::error::Error::Incomplete,
            ciborium_ll::Error::Syntax(_) => crate::error::Error::malformed(format!(
                "invalid initial byte 0x{:02x} at offset {pos}",
                rest[0]
            )),
        })?;
        // RFC 8949 section 3.3: two-byte simple values below 32 are not well-formed.
        if rest[0] == 0xf8 && rest[1] < 32 {
            return Err(crate::error::Error::malformed(format!(
                "invalid simple value encoding at offset {pos}"
            )));
        }
        Ok(Self {
            header,
            len: decoder.offset(),
        })
    }
}
