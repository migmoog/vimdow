use std::io;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum VimdowError {
    #[error("Neovim crashed")]
    NeovimCrashed,

    #[error("IO Error: {0}")]
    IO(io::Error),
}
