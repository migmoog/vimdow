
use godot::{
    classes::{Control, IControl, ProjectSettings},
    obj::WithBaseField,
    prelude::*,
};

mod err;
mod highlights;
mod neovim;

use unicode_segmentation::UnicodeSegmentation;

use crate::highlights::Highlighter;

fn column_slice(row: &str, start: usize, end: usize) -> String {
    assert!(start <= end);
    row.graphemes(true).skip(start).take(end - start).collect()
}

fn get_column(src: &str, pos: &Vector2i) -> String {
    src.lines()
        .nth(pos.y as usize)
        .map(|line| {
            line.graphemes(true)
                .nth(pos.x as usize)
                .unwrap_or(" ")
                .to_string()
        })
        .unwrap_or_else(String::new)
}

#[derive(GodotClass)]
#[class(init, base=Control)]
// Funny name
struct VimdowWindow {
    base: Base<Control>,

    #[export(multiline)]
    text: GString,

    #[init(val = Vector2i {x: -1, y: -1})]
    #[var]
    cursor: Vector2i,

    #[export]
    current_mode: VarDictionary,

    #[init(node = "Highlighter")]
    highlighter: OnReady<Gd<Highlighter>>,
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
            .unwrap_or("")
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
        self.highlighter.bind_mut().set_hl_regions(
            (0..=height)
                .map(|_| {
                    let mut out = PackedInt32Array::new();
                    out.resize(width as usize);
                    out.fill(0);
                    out
                })
                .collect(),
        );

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

        self.highlighter.bind_mut().clear();
    }

    #[func]
    // starts a redraw with the provided highlight data
    fn flush(&mut self, hl: VarDictionary, current_mode: VarDictionary) {
        self.highlighter.bind_mut().set_hl_data(hl);
        self.current_mode = current_mode;
        self.base_mut().queue_redraw();
    }

    fn draw_row(&mut self, row: i32) {
        let ignore_hl: bool = ProjectSettings::singleton()
            .get_setting("vimdow/debug/ignore_hl")
            .try_to()
            .unwrap_or(false);

        let regions = self.highlighter.bind().get_regions(row);
        if !ignore_hl {
            // drawing background colors
            for r in regions.iter() {
                let position = Vector2 {
                    x: r.attr.char_size.x * r.start_col as f32,
                    y: r.attr.char_size.y * row as f32,
                };
                let size = Vector2 {
                    x: r.attr.char_size.x * (r.end_col - r.start_col) as f32,
                    y: r.attr.char_size.y,
                };

                // drawing colored background
                self.base_mut()
                    .draw_rect_ex(Rect2 { position, size }, r.attr.background)
                    .filled(true)
                    .done();
            }
        }

        for r in regions.iter() {
            let text_position = Vector2 {
                x: r.start_col as f32 * r.attr.char_size.x,
                y: row as f32 * r.attr.char_size.y
                    + r.attr
                        .font
                        .get_ascent_ex()
                        .font_size(r.attr.font_size)
                        .done(),
            };

            let region_text = column_slice(&self.get_line(row), r.start_col, r.end_col);

            self.base_mut()
                .draw_string_ex(&r.attr.font, text_position, &region_text)
                .font_size(r.attr.font_size)
                .modulate(if ignore_hl {
                    Color::WHITE
                } else {
                    r.attr.foreground
                })
                .done();
        }
    }

    fn draw_cursor(&mut self) {
        let attr = self.highlighter.bind().get_cursor_attr(&self.cursor);
        let cs = attr.char_size;
        let position = { Vector2::new(self.cursor.x as f32, self.cursor.y as f32) * cs };
        match self.current_mode.at("cursor_shape").to_string().as_str() {
            "block" => {
                self.base_mut()
                    .draw_rect_ex(Rect2 { position, size: cs }, attr.foreground)
                    .filled(true)
                    .done();

                let region_text = get_column(&self.text.to_string().as_str(), &self.cursor);
                self.base_mut()
                    .draw_string_ex(
                        &attr.font,
                        Vector2 {
                            x: position.x,
                            y: position.y
                                + attr.font.get_ascent_ex().font_size(attr.font_size).done(),
                        },
                        &region_text,
                    )
                    .font_size(attr.font_size)
                    .modulate(attr.background)
                    .done();
            }
            "vertical" => {
                self.base_mut().draw_line(
                    position,
                    Vector2 {
                        x: position.x,
                        y: position.y + cs.y,
                    },
                    attr.foreground,
                );
            }
            "horizontal" => {
                self.base_mut().draw_line(
                    Vector2 {
                        x: position.x,
                        y: position.y + cs.y,
                    },
                    Vector2 {
                        x: position.x + cs.x,
                        y: position.y + cs.y,
                    },
                    attr.foreground,
                );
            }
            _ => unreachable!(),
        }
    }
}

#[godot_api]
impl IControl for VimdowWindow {
    fn draw(&mut self) {
        for i in 0..self.get_line_count() {
            self.draw_row(i);
        }

        if self.cursor.x >= 0 && self.cursor.y >= 0 {
            self.draw_cursor();
        }
    }
}

struct Extension;

#[gdextension]
unsafe impl ExtensionLibrary for Extension {}
