enum Pending {
    Items(usize),
    Indefinite { map: bool, items: usize },
    Tag,
    // Chunks of an indefinite-length byte (false) or text (true) string.
    Chunks { text: bool },
}

/// Where a scan of an incomplete item stopped: the offset of the first head it could not read,
/// relative to the start of the item, and the containers open at that point.
#[derive(Default)]
struct Progress {
    resume: usize,
    stack: Vec<Pending>,
}

/// The progress of scanning one item across calls, so a streaming decoder fed in parts scans
/// each byte once rather than once per part.
#[magnus::wrap(class = "Ciborium::Native::ScanState", free_immediately)]
pub(crate) struct ScanState(std::cell::RefCell<Progress>);

impl ScanState {
    pub(crate) fn new() -> Self {
        Self(std::cell::RefCell::new(Progress::default()))
    }

    /// Forgets the progress, for when the next scan starts at another item.
    pub(crate) fn clear(&self) {
        *self.0.borrow_mut() = Progress::default();
    }
}

pub(crate) enum Scan {
    Complete(usize),
    Incomplete,
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

    /// Scans the item at `pos`, continuing from where `state` stopped, and records where this
    /// scan stops when the item is still incomplete.
    pub(crate) fn scan_resuming(
        input: &'a [u8],
        pos: usize,
        max_depth: usize,
        state: &ScanState,
    ) -> Result<Scan, crate::error::Error> {
        let mut progress = state.0.borrow_mut();
        let mut scanner = crate::scan::Scanner::new(input, pos, max_depth);
        if pos + progress.resume <= input.len() {
            scanner.cursor = crate::cursor::Cursor::new(input, pos + progress.resume);
            scanner.stack = std::mem::take(&mut progress.stack);
        }
        let result = scanner.run();
        *progress = match result {
            Ok(Scan::Incomplete) => Progress {
                resume: scanner.cursor.pos() - pos,
                stack: scanner.stack,
            },
            _ => Progress::default(),
        };
        result
    }

    pub(crate) fn scan(&mut self) -> Result<usize, crate::error::Error> {
        match self.run()? {
            Scan::Complete(end) => Ok(end),
            Scan::Incomplete => Err(crate::error::Error::Incomplete),
        }
    }

    /// Scans until the item ends or the input does. On running out of input, the cursor and
    /// stack are left at the start of the head that could not be read in full.
    fn run(&mut self) -> Result<Scan, crate::error::Error> {
        loop {
            let start = self.cursor.pos();
            match self.step(start) {
                Ok(true) => return Ok(Scan::Complete(self.cursor.pos())),
                Ok(false) => {}
                Err(crate::error::Error::Incomplete) => {
                    self.cursor = crate::cursor::Cursor::new(self.cursor.input(), start);
                    return Ok(Scan::Incomplete);
                }
                Err(error) => return Err(error),
            }
        }
    }

    /// Reads one head with its body, if any. Returns true once the top-level item is finished.
    /// Leaves the stack untouched when the input ends before the head and body do.
    fn step(&mut self, start: usize) -> Result<bool, crate::error::Error> {
        let header = self.cursor.head()?;
        if let Some(Pending::Chunks { text }) = self.stack.last() {
            let text = *text;
            match header {
                ciborium_ll::Header::Break => {
                    self.stack.pop();
                    return Ok(self.complete());
                }
                ciborium_ll::Header::Bytes(Some(len)) if !text => {
                    self.cursor.string(Some(len), false)?;
                }
                ciborium_ll::Header::Text(Some(len)) if text => {
                    self.cursor.string(Some(len), true)?;
                }
                _ => {
                    return Err(crate::error::Error::malformed(format!(
                        "invalid chunk in indefinite-length string at offset {start}"
                    )));
                }
            }
            return Ok(false);
        }
        match header {
            ciborium_ll::Header::Positive(_)
            | ciborium_ll::Header::Negative(_)
            | ciborium_ll::Header::Float(_)
            | ciborium_ll::Header::Simple(_)
            | ciborium_ll::Header::Array(Some(0))
            | ciborium_ll::Header::Map(Some(0)) => {}
            ciborium_ll::Header::Bytes(Some(len)) => {
                self.cursor.string(Some(len), false)?;
            }
            ciborium_ll::Header::Text(Some(len)) => {
                self.cursor.string(Some(len), true)?;
            }
            ciborium_ll::Header::Bytes(None) => {
                self.open(Pending::Chunks { text: false })?;
                return Ok(false);
            }
            ciborium_ll::Header::Text(None) => {
                self.open(Pending::Chunks { text: true })?;
                return Ok(false);
            }
            ciborium_ll::Header::Array(Some(n)) => {
                self.open(Pending::Items(n))?;
                return Ok(false);
            }
            ciborium_ll::Header::Map(Some(n)) => {
                self.open(Pending::Items(n.saturating_mul(2)))?;
                return Ok(false);
            }
            ciborium_ll::Header::Array(None) => {
                self.open(Pending::Indefinite {
                    map: false,
                    items: 0,
                })?;
                return Ok(false);
            }
            ciborium_ll::Header::Map(None) => {
                self.open(Pending::Indefinite {
                    map: true,
                    items: 0,
                })?;
                return Ok(false);
            }
            ciborium_ll::Header::Tag(_) => {
                self.open(Pending::Tag)?;
                return Ok(false);
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
        Ok(self.complete())
    }

    fn open(&mut self, pending: Pending) -> Result<(), crate::error::Error> {
        // An indefinite-length string adds no nesting the decoder counts, and holds only chunks,
        // so it is always the innermost entry.
        if !matches!(pending, Pending::Chunks { .. }) && self.stack.len() >= self.max_depth {
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
                // Popped before its string is counted, so never the innermost entry here.
                Some(Pending::Chunks { .. }) => return false,
            }
            self.stack.pop();
        }
    }
}
