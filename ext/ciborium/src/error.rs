/// Failures inside the native extension, raised as the Ruby classes defined in lib/ciborium/errors.rb.
#[derive(Debug)]
pub(crate) enum Error {
    Malformed(String),
    Incomplete,
    Depth(usize),
    Ruby(magnus::Error),
}

impl From<magnus::Error> for Error {
    fn from(error: magnus::Error) -> Self {
        Self::Ruby(error)
    }
}

impl Error {
    pub(crate) fn malformed(message: impl Into<String>) -> Self {
        Self::Malformed(message.into())
    }

    pub(crate) fn into_ruby(self, ruby: &magnus::Ruby) -> magnus::Error {
        let (name, message) = match self {
            Self::Ruby(error) => return error,
            Self::Malformed(message) => ("MalformedError", message),
            Self::Incomplete => ("IncompleteError", "unexpected end of input".to_owned()),
            Self::Depth(max) => ("DepthError", format!("nesting exceeds max_depth ({max})")),
        };
        crate::error::Error::ruby_error(ruby, name, message)
    }

    fn ruby_error(ruby: &magnus::Ruby, name: &str, message: String) -> magnus::Error {
        use magnus::Module as _;
        let class = ruby
            .class_object()
            .const_get::<_, magnus::RModule>("Ciborium")
            .and_then(|module| module.const_get::<_, magnus::ExceptionClass>(name));
        match class {
            Ok(class) => magnus::Error::new(class, message),
            Err(lookup_error) => lookup_error,
        }
    }
}
