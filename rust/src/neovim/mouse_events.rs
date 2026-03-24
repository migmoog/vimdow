use crate::neovim::process::NeovimProcess;
use godot::{
    classes::{InputEvent, InputEventMouse, InputEventMouseButton, InputEventMouseMotion},
    global::{MouseButton, MouseButtonMask},
    prelude::*,
};

fn make_mouse_modifiers(event: Gd<InputEventMouse>) -> String {
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
    modifiers
}

#[derive(Debug)]
pub struct NvimInputMouse {
    button: String,
    action: String,
    modifier: String,
    grid: i32,
    row: i32,
    col: i32,
}

impl NvimInputMouse {
    pub fn from_input_event(
        event: Gd<InputEvent>,
        grid: i32,
        cell_size: Vector2,
    ) -> Option<Self> {
        if let Ok(mb) = event.clone().try_cast::<InputEventMouseButton>() {
            let pos = mb.get_position() / cell_size;
            Self::button(mb, grid, pos)
        } else if let Ok(mm) = event.clone().try_cast::<InputEventMouseMotion>() {
            let pos = mm.get_position() / cell_size;
            Self::motion(mm, grid, pos)
        } else {
            None
        }
    }

    pub fn apply(&self, np: &mut NeovimProcess) -> i32 {
        np.var_request(
            "nvim_input_mouse",
            varray![
                self.button,
                self.action,
                self.modifier,
                self.grid,
                self.row,
                self.col
            ],
        )
    }

    fn motion(event: Gd<InputEventMouseMotion>, grid: i32, pos: Vector2) -> Option<Self> {
        let modifier = make_mouse_modifiers(event.clone().upcast());

        let button = match event.get_button_mask() {
            MouseButtonMask::LEFT => "left",
            MouseButtonMask::RIGHT => "right",
            _ => "move",
        }
        .to_string();
        let action = if event.get_button_mask().ord() != 0 {
            "drag"
        } else {
            "release" // shouldn't matter if it's moved
        }
        .to_string();

        Some(Self {
            button,
            action,
            modifier,
            grid,
            row: pos.y as i32,
            col: pos.x as i32,
        })
    }

    fn button(event: Gd<InputEventMouseButton>, grid: i32, pos: Vector2) -> Option<Self> {
        let modifier = make_mouse_modifiers(event.clone().upcast());
        let mut action = if event.is_pressed() {
            "press"
        } else {
            "release"
        }
        .to_string();

        let wheel_action =
            |s: &str| -> Option<String> { event.is_pressed().then_some(s.to_string()) };

        let btn_idx = event.get_button_index();
        let button = match btn_idx {
            MouseButton::LEFT => "left",
            MouseButton::RIGHT => "right",
            MouseButton::MIDDLE => "middle",
            MouseButton::XBUTTON1 => "x1",
            MouseButton::XBUTTON2 => "x2",
            MouseButton::WHEEL_UP => {
                action = wheel_action("up")?;

                "wheel"
            }
            MouseButton::WHEEL_DOWN => {
                action = wheel_action("down")?;
                "wheel"
            }
            MouseButton::WHEEL_LEFT => {
                action = wheel_action("left")?;
                "wheel"
            }
            MouseButton::WHEEL_RIGHT => {
                action = wheel_action("right")?;
                "wheel"
            }
            _ => return None,
        }
        .to_string();

        Some(Self {
            button,
            action,
            modifier,
            grid,
            row: pos.y as i32,
            col: pos.x as i32,
        })
    }
}
