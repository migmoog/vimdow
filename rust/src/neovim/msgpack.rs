use crate::neovim::ext_types::rmpv_ext_to_godot;
use godot::prelude::*;
use rmpv::Value;

pub fn rmpv_to_godot(v: Value) -> Variant {
    match v {
        Value::Nil => Variant::nil(),
        Value::Array(values) => {
            let mut out = VarArray::new();
            for value in values {
                out.push(&rmpv_to_godot(value));
            }
            out.to_variant()
        }
        Value::Integer(i) => i.as_i64().expect("Not an i64").to_variant(),
        Value::F32(f) => f.to_variant(),
        Value::F64(f) => f.to_variant(),
        Value::Map(map) => {
            let mut dict = vdict! {};
            for (k, v) in map {
                let _ = dict.insert(rmpv_to_godot(k), rmpv_to_godot(v));
            }
            dict.to_variant()
        }
        Value::Ext(t, data) => {
            let e = rmpv_ext_to_godot(t, data);
            if e.is_nil() {
                godot_error!("Unhandled ext type: {t}");
            }
            e
        }
        Value::String(s) => s.into_str().unwrap().to_variant(),
        Value::Boolean(b) => b.to_variant(),
        Value::Binary(bin) => todo!(), // neovim doesn't use this yet
    }
}

pub fn rpc_array_to_vararray(arr: Vec<Value>) -> VarArray {
    rmpv_to_godot(Value::Array(arr))
        .try_to()
        .expect("Couldn't convert to var array")
}
