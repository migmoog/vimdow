use godot::prelude::*;
// Neovim Ext Types

#[derive(GodotConvert)]
#[godot(transparent)]
pub struct Window(i64);

#[derive(GodotConvert)]
#[godot(transparent)]
pub struct Buffer(i64);

#[derive(GodotConvert)]
#[godot(transparent)]
pub struct Tabpage(i64);

pub fn rmpv_ext_to_godot(t: i8, data: Vec<u8>) -> Variant {
    let mut bytes = [0u8; 8];
    bytes[0..8].copy_from_slice(&data);
    let handle = i64::from_le_bytes(bytes);
    match t {
        0 => Buffer(handle).to_variant(),
        1 => Window(handle).to_variant(),
        2 => Tabpage(handle).to_variant(),
        _ => Variant::nil(),
    }
}
