use godot::{classes::CodeEdit, prelude::*};

mod err;
mod neovim;

pub use neovim::NeovimClient;
use neovim::Window;

#[derive(GodotClass)]
#[class(init, base=CodeEdit)]
// Funny name
struct VimdowWindow {
    base: Base<CodeEdit>,
    #[var]
    id: Window,
}

#[godot_api]
impl VimdowWindow {
    #[func]
    fn set_size(&mut self, width: i32, height: i32) {
        let mut row = " ".repeat(width as usize);
        row.push('\n');
        let mut text = row.repeat(height as usize);
        assert_eq!(
            text.remove(text.len() - 1),
            '\n',
            "Should remove last newline"
        );
        self.base_mut().set_text(&text);
    }

    #[func]
    fn clear(&mut self) {
        for i in 0..self.base().get_line_count() {
            let line = self.base().get_line(i).to_string();
            let new_line: String = line
                .chars()
                .map(|c| if c.is_whitespace() { c } else { ' ' })
                .collect();
            self.base_mut().set_line(i, &new_line);
        }
    }
}

struct Extension;

#[gdextension]
unsafe impl ExtensionLibrary for Extension {}
