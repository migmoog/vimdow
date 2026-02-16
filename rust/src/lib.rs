use godot::{
    classes::{Control, IControl},
    prelude::*,
};

mod err;
mod neovim;

pub use neovim::NeovimClient;
use neovim::Window;

#[derive(GodotConvert, Var, Export, Default)]
#[godot(via = GString)]
#[allow(non_camel_case_types)]
enum CursorShape {
    #[default]
    block,
    vertical,
    horizontal,
}

#[derive(GodotClass)]
#[class(init, base=Control)]
// Funny name
struct VimdowWindow {
    base: Base<Control>,

    #[export]
    id: Window,

    #[export(multiline)]
    text: GString,

    #[export]
    cursor_shape: CursorShape,

    #[init(val = Vector2i {x: -1, y: -1})]
    #[var]
    cursor: Vector2i,
}

#[godot_api]
impl VimdowWindow {
    #[func]
    fn get_line_count(&self) -> i32 {
        self.text.to_string().lines().map(|_| 1).sum()
    }

    #[func]
    fn get_line(&self, i: i32) -> String {
        self.text
            .to_string()
            .lines()
            .nth(i as usize)
            .unwrap()
            .into()
    }

    #[func]
    fn get_grid_size(&self) -> Vector2i {
        let y = self.get_line_count();
        let x = self.get_line(0).len() as i32;
        Vector2i { x, y }
    }

    #[func]
    fn set_line(&mut self, i: i32, text: String) {
        self.text = self
            .text
            .to_string()
            .lines()
            .enumerate()
            .map(|(num, line)| if num == i as usize { &text } else { line })
            .collect::<Vec<_>>()
            .join("\n")
            .to_godot();
    }

    #[func]
    fn set_grid_size(&mut self, width: i32, height: i32) {
        let mut row = " ".repeat(width as usize);
        row.push('\n');
        let mut text = row.repeat(height as usize);
        assert_eq!(
            text.remove(text.len() - 1),
            '\n',
            "Should remove last newline"
        );
        self.text = text.to_godot();
    }

    #[func]
    fn clear(&mut self) {
        for i in 0..self.get_line_count() {
            let line = self.get_line(i).to_string();
            let new_line: String = line
                .chars()
                .map(|c| if c.is_whitespace() { c } else { ' ' })
                .collect();
            self.set_line(i, new_line);
        }
    }
}

#[godot_api]
impl IControl for VimdowWindow {
    fn draw(&mut self) {
        let font = self
            .base()
            .get_theme_font_ex("font")
            .theme_type("CodeEdit")
            .done()
            .expect("Should have a font");
        let font_size = self
            .base()
            .get_theme_font_size_ex("font_size")
            .theme_type("CodeEdit")
            .done();
        let char_size = font.get_char_size(' '.into(), font_size);
        let text = self.text.to_string();
        for (i, line) in text.lines().enumerate() {
            self.base_mut()
                .draw_string_ex(&font, Vector2::new(0.0, (i + 1) as f32 * char_size.y), line)
                .font_size(font_size)
                .done();

            let width = 2.0;
            if self.cursor.x >= 0 && self.cursor.y >= 0 {
                let position = Vector2 {
                    x: self.cursor.x as f32 * char_size.x,
                    y: (self.cursor.y as f32 + 0.1) * char_size.y,
                };

                match self.cursor_shape {
                    CursorShape::block => self
                        .base_mut()
                        .draw_rect_ex(
                            Rect2 {
                                position,
                                size: char_size,
                            },
                            Color::WHITE,
                        )
                        .filled(false)
                        .width(width)
                        .done(),
                    CursorShape::vertical => self
                        .base_mut()
                        .draw_line_ex(
                            Vector2 {
                                x: position.x + char_size.x,
                                y: position.y,
                            },
                            Vector2 {
                                x: position.x + char_size.x,
                                y: position.y + char_size.y,
                            },
                            Color::WHITE,
                        )
                        .width(width)
                        .done(),

                    CursorShape::horizontal => self
                        .base_mut()
                        .draw_line_ex(
                            Vector2 {
                                x: position.x,
                                y: position.y + char_size.y,
                            },
                            Vector2 {
                                x: position.x + char_size.x,
                                y: position.y + char_size.y,
                            },
                            Color::WHITE,
                        )
                        .done(),
                };
                // self.base_mut().draw_char(&font, pos, cursor_char);
            }
        }
    }
}

struct Extension;

#[gdextension]
unsafe impl ExtensionLibrary for Extension {}
