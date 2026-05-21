use bitflags::bitflags;
use godot::{
    classes::InputEventKey,
    global::Key,
    obj::{EngineEnum, Gd, Singleton},
};

bitflags! {
    #[derive(Debug, PartialEq)]
    pub struct Modifiers: u8 {
        const NONE = 0;
        const CTRL = 1;
        const ALT = 1 << 1;
        const SHIFT = 1 << 2;
        const META = 1 << 3;
    }
}

#[derive(Debug)]
enum NvimKeycode {
    Named(&'static str),
    Function(String),
    Printable(char),
    Keycode(Key),
}

#[derive(Debug)]
pub struct NvimInput {
    mods: Modifiers,
    nk: NvimKeycode,
}

impl NvimInput {
    pub fn apply_modifiers(&self, s: &str) -> String {
        let mut out = String::from("<");
        for (n, _) in self.mods.iter_names() {
            out.push(n.chars().nth(0).unwrap());
            out.push('-');
        }
        out.push_str(s);
        out.push('>');
        out
    }
}

impl ToString for NvimInput {
    fn to_string(&self) -> String {
        if godot::classes::ProjectSettings::singleton()
            .get_setting("vimdow/debug/log_keys")
            .try_to::<bool>()
            .unwrap_or(false)
        {
            godot::global::godot_print!("Translated input: {:?}, Mods: {:?}", self.nk, self.mods);
        }
        match self.nk {
            NvimKeycode::Printable(c) => {
                let c = c.to_string();
                if self.mods.is_empty() || self.mods == Modifiers::SHIFT {
                    c
                } else {
                    self.apply_modifiers(&c)
                }
            }
            NvimKeycode::Keycode(k) => {
                let mut k = k.as_str().to_string();
                if self.mods.is_empty() {
                    return String::new();
                }

                // keycodes default to caps for labels. 
                // doing this to preserve cases because neovim differentiates between Alt events
                // with case-sensitive characters.
                if !self.mods.contains(Modifiers::SHIFT) {
                    k = k.to_lowercase();
                }
                self.apply_modifiers(&k)
            }
            NvimKeycode::Named(n) => self.apply_modifiers(n),
            NvimKeycode::Function(ref f) => self.apply_modifiers(f),
        }
    }
}

impl From<Gd<InputEventKey>> for NvimInput {
    fn from(value: Gd<InputEventKey>) -> Self {
        let kc = value.get_keycode();
        let mut mods = Modifiers::NONE;
        if value.is_ctrl_pressed() {
            mods.insert(Modifiers::CTRL);
        }

        if value.is_alt_pressed() {
            mods.insert(Modifiers::ALT);
        }

        if value.is_meta_pressed() {
            mods.insert(Modifiers::META);
        }

        if value.is_shift_pressed() {
            mods.insert(Modifiers::SHIFT);
        }
        let nk = match kc {
            Key::ENTER => NvimKeycode::Named("CR"),
            Key::BACKSPACE => NvimKeycode::Named("BS"),
            Key::TAB => NvimKeycode::Named("Tab"),
            Key::ESCAPE => NvimKeycode::Named("Esc"),
            Key::SPACE => NvimKeycode::Named("Space"),
            Key::LEFT => NvimKeycode::Named("Left"),
            Key::RIGHT => NvimKeycode::Named("Right"),
            Key::UP => NvimKeycode::Named("Up"),
            Key::DOWN => NvimKeycode::Named("Down"),
            Key::DELETE => NvimKeycode::Named("Del"),
            _ if (Key::F1.ord()..=Key::F12.ord()).contains(&kc.ord()) => {
                NvimKeycode::Function(format!("F{}", kc.ord() - Key::F1.ord() + 1))
            }
            _ => {
                let uc = value.get_unicode();
                if uc != 0
                    && let Some(c) = char::from_u32(uc)
                {
                    if c == '<' {
                        NvimKeycode::Named("lt")
                    } else {
                        NvimKeycode::Printable(c)
                    }
                } else {
                    NvimKeycode::Keycode(kc)
                }
            }
        };

        Self { mods, nk }
    }
}
