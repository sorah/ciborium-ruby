/// Rules of the CTAP2 canonical CBOR encoding form (CTAP 2.2 section 8), which WebAuthn
/// requires of every CBOR structure it defines.
pub(crate) struct Ctap2;

impl Ctap2 {
    /// Checks the head whose initial byte is `initial` and which parsed as `header`.
    pub(crate) fn check_head(
        initial: u8,
        header: &ciborium_ll::Header,
        start: usize,
    ) -> Result<(), crate::error::Error> {
        let argument = match *header {
            ciborium_ll::Header::Tag(_) => {
                return Err(crate::error::Error::malformed(format!(
                    "tag at offset {start} is not allowed by the ctap2 profile"
                )));
            }
            ciborium_ll::Header::Bytes(None)
            | ciborium_ll::Header::Text(None)
            | ciborium_ll::Header::Array(None)
            | ciborium_ll::Header::Map(None)
            | ciborium_ll::Header::Break => {
                return Err(crate::error::Error::malformed(format!(
                    "indefinite-length item at offset {start} is not allowed by the ctap2 profile"
                )));
            }
            ciborium_ll::Header::Positive(n) | ciborium_ll::Header::Negative(n) => n,
            ciborium_ll::Header::Bytes(Some(len))
            | ciborium_ll::Header::Text(Some(len))
            | ciborium_ll::Header::Array(Some(len))
            | ciborium_ll::Header::Map(Some(len)) => len as u64,
            // Floats keep whatever width they were encoded with.
            ciborium_ll::Header::Float(_) | ciborium_ll::Header::Simple(_) => return Ok(()),
        };
        if initial & 0x1f != crate::canonical::Ctap2::shortest_additional_info(argument) {
            return Err(crate::error::Error::malformed(format!(
                "argument at offset {start} is not in its shortest form"
            )));
        }
        Ok(())
    }

    fn shortest_additional_info(argument: u64) -> u8 {
        match argument {
            0..=23 => argument as u8,
            24..=0xff => 24,
            0x100..=0xffff => 25,
            0x1_0000..=0xffff_ffff => 26,
            _ => 27,
        }
    }

    /// Orders encoded map keys: by major type, then by length, then bytewise.
    pub(crate) fn key_order(a: &[u8], b: &[u8]) -> std::cmp::Ordering {
        (a[0] >> 5)
            .cmp(&(b[0] >> 5))
            .then(a.len().cmp(&b.len()))
            .then(a.cmp(b))
    }
}
