use godot::classes::{
    InputEventKey, InputEventMouse, InputEventMouseButton, InputEventWithModifiers, Os,
};
use godot::global::{Key, KeyModifierMask, MouseButton, MouseButtonMask};
use godot::prelude::*;
use rmpv::Value;
use std::collections::HashMap;
mod ext_types;
mod msgpack;

use crate::neovim::msgpack::rpc_array_to_vararray;
use msgpack::rmpv_to_godot;

mod process;
use process::NeovimProcess;

fn is_special_symbol(kc: Key) -> bool {
    matches!(
        kc,
        Key::BACKSPACE | Key::TAB | Key::ENTER | Key::SPACE | Key::ESCAPE | Key::LESS
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

    #[func]
    fn kill_process(&mut self) {
        if self.nvim_process.is_some() {
            godot_warn!("killed neovim process");
        }
        self.nvim_process = None;
    }

    #[func]
    fn spawn(&mut self, program: String, args: Array<GString>) -> bool {
        let mut args_vec = vec![];
        for i in 0..args.len() {
            let args = args.at(i);
            args_vec.push(args.to_string());
        }
        match NeovimProcess::new(&program, args_vec.as_slice()) {
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
            &(
                width,
                height,
                HashMap::from([("ext_linegrid", true), ("rgb", true)]),
            ),
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

            match kc {
                Key::ENTER => input.push_str(if has_modifier { "CR" } else { "<CR>" }),
                Key::BACKSPACE => input.push_str(if has_modifier { "BS" } else { "<BS>" }),
                Key::TAB => input.push_str(if has_modifier { "Tab" } else { "<Tab>" }),
                Key::ESCAPE => input.push_str(if has_modifier { "Esc" } else { "<Esc>" }),
                Key::SPACE => input.push_str(if has_modifier { "Space" } else { "<Space>" }),
                Key::LESS => input.push_str(if has_modifier { "lt" } else { "<lt>" }),
                Key::DELETE => input.push_str(if has_modifier { "Del" } else { "<Del>" }),
                _ if Key::F1.ord() <= kc.ord() && kc.ord() <= Key::F12.ord() => {
                    let fmt = format!("F{}", kc.ord() - Key::F1.ord() + 1);
                    if has_modifier {
                        input.push_str(&fmt);
                    } else {
                        input.push_str(&format!("<{}>", fmt));
                    }
                }
                _ => {
                    if let Some(c) = char::from_u32(if event.is_ctrl_pressed() {
                        kc.ord() as u32
                    } else {
                        event.get_unicode()
                    }) {
                        input.push(c);
                    }
                }
            }

            if !regular_shifted_symbol && has_modifier {
                input.push('>');
            }
        }

        np.var_request("nvim_input", varray![input.to_godot()]);
        inputs_buffer.clear();
    }

    #[func]
    fn flush_mouse_inputs(
        &mut self,
        grid_index: i32,
        event_position: PackedVector2Array,
        mut inputs_buffer: Array<Gd<InputEventMouse>>,
    ) {
        let Some(np) = self.nvim_process.as_mut() else {
            return;
        };
        assert!(
            event_position.len() == inputs_buffer.len(),
            "Events should have parallel events to positions"
        );
        for (event, &pos) in inputs_buffer.iter_shared().zip(event_position.as_slice()) {
            let mut modifiers = String::new();
            if event.is_ctrl_pressed() {
                modifiers.push('C');
            }
            if event.is_alt_pressed() {
                modifiers.push('A');
            }
            if event.is_shift_pressed() {
                modifiers.push('S');
            }
            if event.is_meta_pressed() {
                modifiers.push('M');
            }
            if let Ok(event) = event.try_cast::<InputEventMouseButton>() {
                let ord = event.get_button_mask().ord();

                let mut action = (ord & MouseButtonMask::LEFT.ord() != 0
                    || ord & MouseButtonMask::RIGHT.ord() != 0)
                    .then_some(if event.is_pressed() {
                        "press"
                    } else {
                        "release"
                    });
                let button = match event.get_button_index() {
                    MouseButton::LEFT => "left",
                    MouseButton::RIGHT => "right",
                    MouseButton::MIDDLE => "middle",
                    MouseButton::XBUTTON1 => "x1",
                    MouseButton::XBUTTON2 => "x2",
                    MouseButton::WHEEL_UP => {
                        action = event.is_pressed().then_some("up");
                        "wheel"
                    }
                    MouseButton::WHEEL_DOWN => {
                        action = event.is_pressed().then_some("down");
                        "wheel"
                    }
                    MouseButton::WHEEL_LEFT => {
                        action = event.is_pressed().then_some("left");
                        "wheel"
                    }
                    MouseButton::WHEEL_RIGHT => {
                        action = event.is_pressed().then_some("right");
                        "wheel"
                    }
                    _ => unreachable!(),
                };

                if let Some(action) = action {
                    np.var_request(
                        "nvim_input_mouse",
                        varray![
                            button,
                            action,
                            modifiers,
                            grid_index,
                            pos.y as i32,
                            pos.x as i32
                        ],
                    );
                } else {
                    godot_warn!("Unimplemented mouse button: {event}");
                }
            }
        }

        inputs_buffer.clear();
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

    fn exit_tree(&mut self) {
        self.kill_process();
    }
}
