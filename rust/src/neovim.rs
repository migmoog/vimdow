use godot::classes::{InputEvent, InputEventKey};
use godot::global::Key;
use godot::prelude::*;
use rmpv::Value;
use std::collections::HashMap;

mod ext_types;
pub use ext_types::*;
mod msgpack;

use crate::neovim::msgpack::rpc_array_to_vararray;
use msgpack::rmpv_to_godot;

mod process;
use process::NeovimProcess;

fn keyevent_to_nvim_symbol(key_event: Gd<InputEventKey>) -> String {
    match key_event.get_keycode() {
        Key::BACKSPACE => "<BS>".into(),
        Key::TAB => "<Tab>".into(),
        Key::ENTER => "<CR>".into(),
        Key::ESCAPE => "<Esc>".into(),
        Key::SPACE => "<Space>".into(),
        Key::DELETE => "<Del>".into(),
        Key::UP => "<Up>".into(),
        Key::LEFT => "<Left>".into(),
        Key::RIGHT => "<Right>".into(),
        Key::DOWN => "<Down>".into(),

        code if Key::F1.ord() <= code.ord() && code.ord() <= Key::F35.ord() => {
            format!("<F{}>", code.ord() - Key::F1.ord() + 1)
        }

        Key::PAGEUP => "<PageUp>".into(),
        Key::PAGEDOWN => "<PageDown>".into(),

        _ => GString::chr(key_event.get_unicode() as i64).to_string(), // TODO: keypad keys
    }
}

// for info on the modifiers: ":h keycodes"
enum Modifier {
    Shift,
    Ctrl,
    Alt,
    Super,
    // no meta key, not sure where it's needed
}

impl Modifier {
    fn modify(&self, event: Gd<InputEventKey>) -> String {
        let chr = char::from_u32(event.get_unicode()).expect("Not a parseable char");
        match self {
            Modifier::Shift => {
                format!("<S-{}>", chr)
            }
            Modifier::Ctrl => {
                format!("<C-{}>", chr)
            }
            Modifier::Alt => {
                format!("<A-{}>", chr)
            }
            Modifier::Super => {
                format!("<D-{}>", chr)
            }
        }
    }

    fn from_keycode(code: Key) -> Option<Self> {
        match code {
            Key::CTRL => Some(Self::Ctrl),
            Key::ALT => Some(Self::Alt),
            Key::SHIFT => Some(Self::Shift),
            Key::META => Some(Self::Super),
            _ => None,
        }
    }
}

#[derive(GodotClass)]
#[class(base=Node, init)]
pub struct NeovimClient {
    base: Base<Node>,
    nvim_process: Option<NeovimProcess>,

    // any key that has something attached to it (ex: <C-...>)
    modifier: Option<Modifier>,
}

#[godot_api]
impl NeovimClient {
    #[signal]
    fn neovim_event(method: String, params: VarArray);

    #[signal]
    fn neovim_response(msgid: i32, error: Variant, result: Variant);

    #[func]
    fn kill_process(&mut self) {
        if self.nvim_process.is_some() {
            godot_warn!("killed neovim process");
        }
        self.nvim_process = None;
    }

    #[func]
    fn spawn(&mut self, program: String) -> bool {
        match NeovimProcess::new(&program) {
            Ok(np) => {
                self.nvim_process = Some(np);
                true
            }
            Err(e) => {
                godot_error!("Couldn't start neovim process: {e:?}");
                false
            }
        }
    }

    #[func]
    fn attach(&mut self, width: i32, height: i32) -> bool {
        let Some(ref mut np) = self.nvim_process else {
            godot_error!("Tried attaching to process while none was running");
            return false;
        };

        // NOTE: in the future, may want to add a "multigrid" option if users want to
        // edit buffers in separate windows.
        np.request(
            "nvim_ui_attach",
            &(width, height, HashMap::from([("ext_linegrid", true)])),
        );
        true
    }

    #[func]
    fn request(&mut self, method: String, params: VarArray) -> i32 {
        let Some(ref mut np) = self.nvim_process else {
            return -1;
        };
        np.var_request(&method, params)
    }

    #[func]
    fn is_running(&self) -> bool {
        self.nvim_process.is_some()
    }
}

#[godot_api]
impl INode for NeovimClient {
    fn process(&mut self, _delta: f32) {
        let mut messages = vec![];
        while let Some(Some(v)) = self.nvim_process.as_mut().map(|p| p.check()) {
            if let Value::Array(rpc) = v {
                messages.push(rpc);
            } else {
                godot_error!("not an array: {v:?}");
            }
        }

        for rpc in messages {
            let msgtype = rpc.get(0).and_then(|v| v.as_u64()).unwrap_or(99);
            match msgtype {
                2 => {
                    if let [Value::String(method), Value::Array(params)] = &rpc[1..3] {
                        let params = rpc_array_to_vararray(params.clone());
                        self.signals()
                            .neovim_event()
                            .emit(method.to_owned().into_str().unwrap(), &params);
                    }
                }
                1 => {
                    if let [Value::Integer(msgid), error, result] = &rpc[1..4] {
                        self.signals().neovim_response().emit(
                            msgid.as_i64().unwrap() as i32,
                            &rmpv_to_godot(error.to_owned()),
                            &rmpv_to_godot(result.to_owned()),
                        );
                    }
                }
                0 => godot_warn!("Haven't implemented requests yet"),
                _ => godot_error!("Got a non-existent message type: {msgtype}"),
            }
        }
    }

    fn unhandled_key_input(&mut self, event: Gd<InputEvent>) {
        let (true, Ok(key_event)) = (self.nvim_process.is_some(), event.try_cast::<InputEventKey>())
        else {
            return;
        };

        if let Some(modifier) = Modifier::from_keycode(key_event.get_keycode()) {
            self.modifier = match self.modifier {
                Some(_) if key_event.is_released() => None,
                None if key_event.is_pressed() => Some(modifier),
                _ => None,
            };
            return;
        }

        if key_event.is_pressed() {
            let input = match &self.modifier {
                Some(m) => m.modify(key_event),
                None => keyevent_to_nvim_symbol(key_event),
            };

            self.request("nvim_input".to_string(), varray![input]);
        }
    }

    fn exit_tree(&mut self) {
        self.kill_process();
    }
}
