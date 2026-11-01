/// Errors returned to Swift.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum BloomError {
    /// A file system error, with the system's message.
    #[error("{msg}")]
    Io {
        /// Human-readable description.
        msg: String,
    },
    /// The job was cancelled before it finished.
    #[error("cancelled")]
    Cancelled,
}

impl From<std::io::Error> for BloomError {
    fn from(e: std::io::Error) -> Self {
        BloomError::Io { msg: e.to_string() }
    }
}
