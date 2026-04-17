use godot::classes::{InputEvent, InputEventKey, ProjectSettings};
use godot::global::Key;
use godot::prelude::*;
use rmpv::Value;
use std::collections::HashMap;
mod ext_types;
mod msgpack;

use crate::neovim::mouse_events::NvimInputMouse;
use crate::neovim::msgpack::rpc_array_to_vararray;
use msgpack::rmpv_to_godot;

mod process;
use process::NeovimProcess;

mod mouse_events;

fn is_special_symbol(kc: Key) -> bool {
    matches!(
        kc,
        Key::BACKSPACE | Key::TAB | Key::ENTER | Key::SPACE | Key::ESCAPE
    )
}

#[derive(GodotClass)]
#[class(tool, base=Node, init)]
pub struct NeovimClient {
    base: Base<Node>,
    nvim_process: Option<NeovimProcess>,
}

#[godot_api]
impl NeovimClient {
    #[signal]
    fn neovim_event(method: String, params: VarArray);

    #[signal]
    fn neovim_response(msgid: i32, error: Variant, result: Variant);

    #[signal]
    fn neovim_request(msgid: i32, method: String, params: VarArray);

    #[signal]
    fn neovim_quit(status: i32);

    #[func]
    fn kill_process(&mut self) {
        if self.nvim_process.is_some() {
            godot_warn!("Killed neovim process");
        }
        self.nvim_process = None;
    }

    #[func]
    fn spawn(&mut self, program: String, args: PackedStringArray) -> bool {
        let args: Vec<_> = args.to_vec().into_iter().map(|g| g.to_string()).collect();
        match NeovimProcess::new(&program, args.as_slice()) {
            Ok(np) => {
                self.nvim_process = Some(np);
                true
            }
            Err(e) => {
                godot_error!("Couldn't start neovim process: {:?}", e);
                false
            }
        }
    }

    #[func]
    fn request(&mut self, method: String, params: VarArray) -> i32 {
        let Some(np) = self.nvim_process.as_mut() else {
            return -1;
        };
        np.var_request(&method, params)
    }

    #[func]
    fn respond(&mut self, msgid: i32, error: Variant, result: Variant) {
        let Some(np) = self.nvim_process.as_mut() else {
            return;
        };
        np.var_respond(msgid, error, result);
    }

    #[func]
    fn is_running(&mut self) -> bool {
        match &mut self.nvim_process {
            Some(np) => np.is_running(),
            None => false,
        }
    }

    #[func]
    fn flush_key_inputs(&mut self, mut inputs_buffer: Array<Gd<InputEventKey>>) {
        let Some(np) = self.nvim_process.as_mut() else {
            return;
        };
        let mut input = String::new();
        for event in inputs_buffer.iter_shared() {
            let kc = event.get_keycode();
            // ignore modifier key events, should be lumped in with other inputs
            if matches!(kc, Key::CTRL | Key::META | Key::SHIFT | Key::ALT) {
                continue;
            }

            let map = HashMap::from([
                ('C', event.is_ctrl_pressed()),
                ('A', event.is_alt_pressed()),
                ('M', event.is_meta_pressed()),
                ('S', event.is_shift_pressed()),
            ]);

            let only_shift = map
                .iter()
                .all(|(&c, &is_set)| if c == 'S' { is_set } else { !is_set });
            let has_modifier = map.iter().any(|(_, &is_set)| is_set);
            let regular_shifted_symbol = only_shift && !is_special_symbol(kc);
            if !regular_shifted_symbol && has_modifier {
                input.push('<');
                for c in map
                    .into_iter()
                    .filter_map(|(c, is_set)| is_set.then_some(c))
                {
                    input.push(c);
                    input.push('-');
                }
            }

            let mut special_key = |pattern: &str| {
                let f = format!("<{pattern}>");
                input.push_str(if has_modifier { pattern } else { f.as_str() });
            };

            match kc {
                Key::ENTER => special_key("CR"),
                Key::BACKSPACE => special_key("BS"),
                Key::TAB => special_key("Tab"),
                Key::ESCAPE => special_key("Esc"),
                Key::SPACE => special_key("Space"),
                Key::DELETE => special_key("Del"),
                Key::LEFT => special_key("Left"),
                Key::RIGHT => special_key("Right"),
                Key::UP => special_key("Up"),
                Key::DOWN => special_key("Down"),
                _ if Key::F1.ord() <= kc.ord() && kc.ord() <= Key::F12.ord() => {
                    let fmt = format!("F{}", kc.ord() - Key::F1.ord() + 1);
                    // input.push_str(&special_key(&fmt));
                    special_key(&fmt);
                }
                _ => {
                    if let Some(c) = char::from_u32(if event.is_ctrl_pressed() {
                        kc.ord() as u32
                    } else {
                        event.get_unicode()
                    }) {
                        if c == '<' {
                            input.push_str("<lt>");
                        } else {
                            input.push(c);
                        }
                    }
                }
            }

            if !regular_shifted_symbol && has_modifier {
                input.push('>');
            }
        }

        let print_key_inputs = ProjectSettings::singleton()
            .get_setting("vimdow/debug/print_key_inputs")
            .try_to()
            .unwrap_or(false);
        if print_key_inputs {
            godot_print!("{}", input);
        }

        np.var_request("nvim_input", varray![&input.to_godot()]);
        inputs_buffer.clear();
    }

    #[func]
    fn flush_mouse_inputs(
        &mut self,
        grid_index: i32,
        mut inputs_buffer: Array<Gd<InputEvent>>,
        cell_size: Vector2,
    ) {
        let Some(np) = self.nvim_process.as_mut() else {
            return;
        };

        for event in inputs_buffer.iter_shared() {
            if let Some(nim) = NvimInputMouse::from_input_event(event, grid_index, cell_size) {
                nim.apply(np);
            }
        }

        inputs_buffer.clear();
    }
}

#[godot_api]
impl INode for NeovimClient {
    fn process(&mut self, _delta: f32) {
        let Some(np) = self.nvim_process.as_mut() else {
            return;
        };

        if let Ok(Some(e)) = np.try_wait() {
            self.signals().neovim_quit().emit(e.code().unwrap_or(-1));
            return;
        }

        let mut messages = vec![];
        while let Some(v) = np.check() {
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
                0 => {
                    if let [
                        Value::Integer(msgid),
                        Value::String(method),
                        // Value::Array(params),
                        // method,
                        params,
                    ] = &rpc[1..4]
                    {
                        self.signals().neovim_request().emit(
                            msgid.as_i64().unwrap() as i32,
                            method.to_string(),
                            &rmpv_to_godot(params.to_owned()).to(),
                        );
                    }
                }
                _ => godot_error!("Got a non-existent message type: {msgtype}"),
            }
        }
    }
}
