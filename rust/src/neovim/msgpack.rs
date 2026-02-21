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

pub fn godot_to_rmpv(v: Variant) -> Value {
    let t = v.get_type();
    match t {
        VariantType::NIL => Value::Nil,
        VariantType::ARRAY => {
            let mut out = Vec::new();
            let v = v.to::<Vec<Variant>>();
            for var in v {
                out.push(godot_to_rmpv(var));
            }

            Value::Array(out)
        }
        VariantType::BOOL => Value::Boolean(v.to()),
        VariantType::INT => {
            if let Ok(int64) = v.try_to::<i64>() {
                Value::Integer(int64.into())
            } else if let Ok(uint64) = v.try_to::<u64>() {
                Value::Integer(uint64.into())
            } else {
                panic!("Can't turn {v} into msgpack int");
            }
        }
        VariantType::FLOAT => {
            if let Ok(float32) = v.try_to::<f32>() {
                Value::F32(float32)
            } else if let Ok(float64) = v.try_to::<f64>() {
                Value::F64(float64)
            } else {
                panic!("Can't turn {v} into msgpack float");
            }
        }
        VariantType::STRING => Value::String(v.to_string().into()),
        VariantType::STRING_NAME => Value::String(v.to_string().into()),
        VariantType::DICTIONARY => Value::Map(
            v.to::<VarDictionary>()
                .iter_shared()
                .map(|(v1, v2)| (godot_to_rmpv(v1), godot_to_rmpv(v2)))
                .collect(),
        ),
        _ => panic!("Can't represent {t:?} as message pack")
    }
}

pub fn rgb_to_color(rgb: i32) -> Color {
    Color {
        r: ((rgb >> 16) & 0xFF) as f32 / 255.0,
        g: ((rgb >> 8) & 0xFF) as f32 / 255.0,
        b: (rgb & 0xFF) as f32 / 255.0,
        a: 1.0
    }
}

pub fn rpc_array_to_vararray(arr: Vec<Value>) -> VarArray {
    rmpv_to_godot(Value::Array(arr))
        .try_to()
        .expect("Couldn't convert to var array")
}
