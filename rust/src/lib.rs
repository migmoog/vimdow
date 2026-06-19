use godot::prelude::*;

mod neovim;
mod render;

struct Extension;

#[gdextension]
unsafe impl ExtensionLibrary for Extension {}
