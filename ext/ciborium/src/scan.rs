enum Pending {
    Items(usize),
    Indefinite { map: bool, items: usize },
    Tag,
}

/// Finds where the data item at `pos` ends without building Ruby objects, checking the same
/// well-formedness rules as the decoder except those that need the decoded values.
pub(crate) struct Scanner<'a> {
    cursor: crate::cursor::Cursor<'a>,
    max_depth: usize,
    stack: Vec<Pending>,
}

impl<'a> Scanner<'a> {
    pub(crate) fn new(input: &'a [u8], pos: usize, max_depth: usize) -> Self {
        Self {
            cursor: crate::cursor::Cursor::new(input, pos),
            max_depth,
            stack: Vec::new(),
        }
    }

    pub(crate) fn scan(&mut self) -> Result<usize, crate::error::Error> {
        loop {
            let start = self.cursor.pos();
            match self.cursor.head()? {
                ciborium_ll::Header::Positive(_)
                | ciborium_ll::Header::Negative(_)
                | ciborium_ll::Header::Float(_)
                | ciborium_ll::Header::Simple(_)
                | ciborium_ll::Header::Array(Some(0))
                | ciborium_ll::Header::Map(Some(0)) => {}
                ciborium_ll::Header::Bytes(len) => {
                    self.cursor.string(len, false)?;
                }
                ciborium_ll::Header::Text(len) => {
                    self.cursor.string(len, true)?;
                }
                ciborium_ll::Header::Array(Some(n)) => {
                    self.open(Pending::Items(n))?;
                    continue;
                }
                ciborium_ll::Header::Map(Some(n)) => {
                    self.open(Pending::Items(n.saturating_mul(2)))?;
                    continue;
                }
                ciborium_ll::Header::Array(None) => {
                    self.open(Pending::Indefinite {
                        map: false,
                        items: 0,
                    })?;
                    continue;
                }
                ciborium_ll::Header::Map(None) => {
                    self.open(Pending::Indefinite {
                        map: true,
                        items: 0,
                    })?;
                    continue;
                }
                ciborium_ll::Header::Tag(_) => {
                    self.open(Pending::Tag)?;
                    continue;
                }
                ciborium_ll::Header::Break => match self.stack.last() {
                    Some(Pending::Indefinite { map, items }) if !map || items % 2 == 0 => {
                        self.stack.pop();
                    }
                    _ => {
                        return Err(crate::error::Error::malformed(format!(
                            "unexpected break at offset {start}"
                        )));
                    }
                },
            }
            if self.complete() {
                return Ok(self.cursor.pos());
            }
        }
    }

    fn open(&mut self, pending: Pending) -> Result<(), crate::error::Error> {
        if self.stack.len() >= self.max_depth {
            return Err(crate::error::Error::Depth(self.max_depth));
        }
        self.stack.push(pending);
        Ok(())
    }

    /// Counts a finished item against its enclosing containers. Returns true once the top-level
    /// item is finished.
    fn complete(&mut self) -> bool {
        loop {
            match self.stack.last_mut() {
                None => return true,
                Some(Pending::Items(n)) => {
                    *n -= 1;
                    if *n > 0 {
                        return false;
                    }
                }
                Some(Pending::Indefinite { items, .. }) => {
                    *items += 1;
                    return false;
                }
                Some(Pending::Tag) => {}
            }
            self.stack.pop();
        }
    }
}
