use godot::classes::{InputEvent, InputEventKey, ProjectSettings};
use godot::global::Key;
use godot::prelude::*;
use rmpv::Value;
mod ext_types;
mod msgpack;

use crate::neovim::key_events::NvimInput;
use crate::neovim::mouse_events::NvimInputMouse;
use crate::neovim::msgpack::rpc_array_to_vararray;
use msgpack::rmpv_to_godot;

mod process;
use process::NeovimProcess;

mod key_events;
mod mouse_events;

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

            let ni = NvimInput::from(event);
            input.push_str(&ni.to_string());
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
