use godot::prelude::*;
use serde::Serialize;
use std::io::Write;
use std::process::{Child, Command, Stdio};
use std::sync::mpsc;
use std::thread::{self, JoinHandle};

use rmpv::Value;

use crate::err::VimdowError;
use crate::neovim::msgpack::godot_to_rmpv;

pub struct NeovimProcess {
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
    pub fn new(program: &str) -> Result<Self, VimdowError> {
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
                    if let Err(e) = stdin.write_all(&buf[..]) {
                        godot_error!("Couldn't write to neovim: {e}");
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

    pub fn check(&self) -> Option<Value> {
        self.from.try_recv().ok()
    }

    fn send_msgpack<T>(&self, args: &T)
    where
        T: Serialize + Sized,
    {
        let buf = rmp_serde::encode::to_vec(args).expect("Couldn't convert args to msgpack");
        self.to.send(buf).expect("Couldn't send to write thread");
    }

    pub fn request<T>(&self, method: &str, params: &T)
    where
        T: Serialize + Sized,
    {
        self.send_msgpack(&(0, self.msgid, method, params));
    }

    pub fn var_request(&mut self, method: &str, params: VarArray) {
        let rpc = varray![0, self.msgid, method, params];
        let val = godot_to_rmpv(rpc.to_variant());
        let mut buf = Vec::new();
        rmpv::encode::write_value(&mut buf, &val).expect("Couldn't serialize value");
        self.msgid += 1;

        self.to.send(buf).expect("Couldn't send serialized variant");
    }
}
