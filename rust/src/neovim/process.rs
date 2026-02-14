use godot::prelude::*;
use serde::Serialize;
use std::collections::HashSet;
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
    pending_requests: HashSet<u32>,
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
            pending_requests: HashSet::new()
        })
    }

    pub fn check(&mut self) -> Option<Value> {
        let v = self.from.try_recv().ok()?;

        if let Value::Array(ref vec) = v
            && let [Value::Integer(msgtype), Value::Integer(msgid), ..] = vec.as_slice()
            && let Some(1) = msgtype.as_i64()
        {
            let msgid = msgid.as_u64().unwrap() as u32;
            assert!(
                self.pending_requests.remove(&msgid),
                "No msgid ({msgid}), exists"
            );
        }

        Some(v)
    }

    fn send_msgpack<T>(&self, args: &T)
    where
        T: Serialize + Sized,
    {
        let buf = rmp_serde::encode::to_vec(args).expect("Couldn't convert args to msgpack");
        self.to.send(buf).expect("Couldn't send to write thread");
    }

    pub fn request<T>(&mut self, method: &str, params: &T)
    where
        T: Serialize + Sized,
    {
        let ogid = self.msgid;
        self.send_msgpack(&(0, ogid, method, params));
        self.msgid += 1;
        self.pending_requests.insert(ogid);
    }

    pub fn var_request(&mut self, method: &str, params: VarArray) -> i32 {
        let ogid = self.msgid;
        let rpc = varray![0, ogid, method, params];
        let val = godot_to_rmpv(rpc.to_variant());
        let mut buf = Vec::new();
        rmpv::encode::write_value(&mut buf, &val).expect("Couldn't serialize value");
        self.msgid += 1;
        self.pending_requests.insert(ogid);

        // self.to.send(buf).expect("Couldn't send serialized variant");
        match self.to.send(buf) {
            Err(se) => {godot_error!("{se}")}
            _ => {}
        }

        ogid as i32
    }
}
