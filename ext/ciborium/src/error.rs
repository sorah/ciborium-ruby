/// Failures inside the native extension, raised as the Ruby classes defined in lib/ciborium/errors.rb.
#[derive(Debug)]
pub(crate) enum Error {
    Malformed(String),
    Incomplete,
    Depth(usize),
    Encode(String),
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

    pub(crate) fn message(&self) -> String {
        match self {
            Self::Ruby(error) => error.to_string(),
            Self::Malformed(message) | Self::Encode(message) => message.clone(),
            Self::Incomplete => "unexpected end of input".to_owned(),
            Self::Depth(max) => format!("nesting exceeds max_depth ({max})"),
        }
    }

    pub(crate) fn into_ruby(self, ruby: &magnus::Ruby) -> magnus::Error {
        let name = match self {
            Self::Ruby(error) => return error,
            Self::Malformed(_) => "MalformedError",
            Self::Incomplete => "IncompleteError",
            Self::Depth(_) => "DepthError",
            Self::Encode(_) => "EncodeError",
        };
        crate::error::Error::ruby_error(ruby, name, self.message())
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
