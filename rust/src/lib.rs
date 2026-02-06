use godot::prelude::*;

mod err;
mod neovim;

pub use neovim::NeovimClient;

struct Extension;

#[gdextension]
unsafe impl ExtensionLibrary for Extension {}
