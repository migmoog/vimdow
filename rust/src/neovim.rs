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

/// Node that's responsible for communicating with the embedded neovim process.
/// will check for events in idle process time and emit them via signals,
/// and can utilize neovim RPC via `NeovimClient.request`
#[derive(GodotClass)]
#[class(tool, base=Node, init)]
pub struct NeovimClient {
    base: Base<Node>,
    nvim_process: Option<NeovimProcess>,
}

#[godot_api]
impl NeovimClient {

    /// Emits on an RPC notification from neovim (msgtype 2)
    #[signal]
    fn neovim_event(method: String, params: VarArray);

    /// Emits on an RPC response from neovim (msgtype 1)
    #[signal]
    fn neovim_response(msgid: i32, error: Variant, result: Variant);

    /// Emits on an RPC request from neovim (msgtype 0)
    #[signal]
    fn neovim_request(msgid: i32, method: String, params: VarArray);

    /// Emits if the embedded neovim process quits unexpectedly, with the appropriate error 
    /// code.
    #[signal]
    fn neovim_quit(status: i32);

    /// Kills the neovim process. Will push a warning once it does.
    #[func]
    fn kill_process(&mut self) {
        if self.nvim_process.is_some() {
            godot_warn!("Killed neovim process");
        }
        self.nvim_process = None;
    }

    /// Spawns a neovim process with the specified binary path
    ///
    /// # Examples
    /// ```
    /// # spawns the embedded process vimdow needs to work
    /// client.spawn("/usr/bin/nvim", PackedStringArray(["--embed"]))
    /// ```
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

    /// Sends an RPC request to the neovim process. Returns the message id of the request
    /// for validation.
    ///
    /// # Examples
    /// ```
    /// # Tells neovim to print hello world to its own console
    /// client.request("nvim_input", ":echo \"hello world!\"<CR>")
    /// ```
    #[func]
    fn request(&mut self, method: String, params: VarArray) -> i32 {
        let Some(np) = self.nvim_process.as_mut() else {
            return -1;
        };
        np.var_request(&method, params)
    }

    /// Sends an RPC response to the neovim process. Will fail if there was no request
    /// made with the provided `msgid`. `error` should be provided a value on failure,
    /// `result` should be provided a value on success.
    ///
    /// # Examples
    /// ```
    /// # Responds to a request with msgid=1 and tell that it failed
    /// client.respond(
    ///     1,
    ///     "This string would signify a failure",
    ///     null
    /// )
    ///
    /// # Responds to a request with msgid=2 and tell that it succeeded
    /// client.respond(
    ///     2,
    ///     null,
    ///     """
    ///     This would be the expected returned value of the rpc call.
    ///     It could also be null if the RPC request isn't expecting a value.
    ///     """
    /// )
    /// ```
    #[func]
    fn respond(&mut self, msgid: i32, error: Variant, result: Variant) {
        let Some(np) = self.nvim_process.as_mut() else {
            return;
        };
        np.var_respond(msgid, error, result);
    }

    /// Returns true if the neovim process is still active. 
    /// Otherwise it returns false if the process hasn't started
    /// or if it died.
    #[func]
    fn is_running(&mut self) -> bool {
        match &mut self.nvim_process {
            Some(np) => np.is_running(),
            None => false,
        }
    }

    /// Reads a buffer of InputEventKeys and translates them to neovim inputs.
    /// Will clear the provided buffer.
    #[func]
    fn flush_key_inputs(&mut self, mut inputs_buffer: Array<Gd<InputEventKey>>) {
        let Some(np) = self.nvim_process.as_mut() else {
            return;
        };
        let mut input = String::new();
        for event in inputs_buffer.iter_shared() {
            let kc = event.get_keycode();
            // ignore modifier key events, should be lumped in with other inputs
            if matches!(
                kc,
                Key::CTRL | Key::META | Key::SHIFT | Key::ALT | Key::CAPSLOCK
            ) {
                continue;
            }

            let ni = NvimInput::from(event);
            input.push_str(&ni.to_string());
        }

        if ProjectSettings::singleton()
            .get_setting_ex("vimdow/debug/log_keys")
            .default_value(&false.to_variant())
            .done()
            .to::<bool>()
        {
            godot_print!("{}", input);
        }
        np.var_request("nvim_input", varray![&input.to_godot()]);

        inputs_buffer.clear();
    }

    /// Reads a buffer of InputEvents. If the events are castable
    /// to mouse events, it will translate them to neovim inputs.
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
                    if let [Value::Integer(msgid), Value::String(method), params] = &rpc[1..4] {
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
