use godot::classes::InputEvent;
use godot::prelude::*;
use rmpv::Value;
use serde::Serialize;
use std::collections::HashMap;
use std::io::Write;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc;
use std::thread::{self, JoinHandle};

mod ext_types;
mod msgpack;

use crate::err::VimdowError;
use crate::neovim::msgpack::rpc_array_to_vararray;
use msgpack::rmpv_to_godot;

struct NeovimProcess {
    _child: Child,
    _from_handle: JoinHandle<()>,
    _to_handle: JoinHandle<()>,
    // the receiver that takes the decoded mspack values
    from: mpsc::Receiver<Value>,
    // the sender that writes encoded mspack values
    to: mpsc::Sender<Vec<u8>>,
    msgid: u32,
}

impl NeovimProcess {
    fn new(program: &str) -> Result<Self, VimdowError> {
        let mut child = Command::new(program)
            .arg("--embed")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(VimdowError::IO)?;

        let (to, recv_in_process) = mpsc::channel::<Vec<u8>>();
        let mut stdin = child.stdin.take().expect("Stdin is not available");
        let to_handle = thread::spawn(move || {
            loop {
                if let Ok(buf) = recv_in_process.recv() {
                    let l = buf.len();
                    match stdin.write(&buf[..]) {
                        Ok(n) => {
                            godot_error!("Only wrote {n}/{} bytes to neovim", l)
                        }
                        Err(e) => {
                            godot_error!("Couldn't write to neovim: {e}");
                        }
                    }
                }
            }
        });

        let (send_from_process, from) = mpsc::channel();
        let mut stdout = child.stdout.take().expect("Stdout is not available");
        let from_handle = thread::spawn(move || {
            loop {
                if let Ok(value) = rmpv::decode::read_value(&mut stdout) {
                    send_from_process
                        .send(value)
                        .expect("Couldn't send decoded value");
                }
            }
        });

        Ok(Self {
            _child: child,
            to,
            from,
            _from_handle: from_handle,
            _to_handle: to_handle,
            msgid: 0,
        })
    }

    fn check(&self) -> Option<Value> {
        self.from.try_recv().ok()
    }

    fn send_msgpack<T>(&self, args: &T)
    where
        T: Serialize + Sized,
    {
        let buf = rmp_serde::encode::to_vec(args).expect("Couldn't convert args to msgpack");
        self.to.send(buf).expect("Couldn't send to write thread");
    }

    fn request<T>(&self, method: &str, params: &T)
    where
        T: Serialize + Sized,
    {
        self.send_msgpack(&(0, self.msgid, method, params));
    }
}

#[derive(GodotClass)]
#[class(init, base=Node)]
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
        let Some(ref np) = self.nvim_process else {
            godot_error!("Tried attaching to process while none was running");
            return false;
        };

        np.request(
            "nvim_ui_attach",
            &(width, height, HashMap::from([("ext_linegrid", true)])),
        );
        true
    }
}

#[godot_api]
impl INode for NeovimClient {
    fn process(&mut self, _delta: f32) {
        if let Some(Some(value)) = self.nvim_process.as_ref().map(|p| p.check()) {
            if let Value::Array(rpc) = value {
                let msgtype = rpc.get(0).and_then(|v| v.as_u64()).unwrap_or(99);
                match msgtype {
                    2 => {
                        if let [Value::String(method), Value::Array(params)] = &rpc[1..3] {
                            let params = rpc_array_to_vararray(params.clone());
                            self.signals()
                                .neovim_event()
                                .emit(method.to_string(), &params);
                        }
                    }
                    1 => {
                        if let [Value::Integer(msgid), error, result] = &rpc[1..4] {
                            self.signals().neovim_response().emit(
                                msgid.as_i64().unwrap() as i32,
                                &rmpv_to_godot(error.clone()),
                                &rmpv_to_godot(result.clone()),
                            );
                        }
                    }
                    0 => godot_warn!("Haven't implemented requests yet"),
                    _ => godot_error!("Got a non-existent message type: {msgtype}"),
                }
            }
        }
    }

    fn unhandled_key_input(&mut self, _event: Gd<InputEvent>) {}
}
