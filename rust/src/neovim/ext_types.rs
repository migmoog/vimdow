use godot::prelude::*;
// Neovim Ext Types

#[derive(GodotConvert, Default, Var, Export)]
#[godot(transparent)]
pub struct Window(i64);

#[derive(GodotConvert, Default, Var, Export)]
#[godot(transparent)]
pub struct Buffer(i64);

#[derive(GodotConvert, Default, Var, Export)]
#[godot(transparent)]
pub struct Tabpage(i64);

pub fn rmpv_ext_to_godot(t: i8, data: Vec<u8>) -> Variant {
    let decoded = rmpv::decode::read_value(&mut data.as_slice()).map(|d| d.as_u64().unwrap_or(99));
    if let Ok(handle) = decoded {
        match t {
            0 => Buffer(handle as i64).to_variant(),
            1 => Window(handle as i64).to_variant(),
            2 => Tabpage(handle as i64).to_variant(),
            _ => Variant::nil(),
        }
    } else {
        Variant::nil()
    }
}
