use std::f64::consts::TAU;

use godot::classes::{Control, IControl, ProjectSettings};
use godot::global::cos;
use godot::{obj::WithBaseField, prelude::*};

mod err;
mod highlights;
mod neovim;

use ropey::Rope;
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
#[class(tool, init, base=Control)]
// Funny name
struct VimdowWindow {
    base: Base<Control>,

    grid_text: Rope,

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
        self.grid_text.len_lines() as i32
    }

    #[func]
    fn get_line(&self, i: i32) -> String {
        self.grid_text.line(i as usize).to_string()
    }

    #[func]
    fn get_grid_size(&self) -> Vector2i {
        let y = self.get_line_count();
        let x = self.get_line(0).len() as i32;
        Vector2i { x, y }
    }

    #[func]
    fn set_line(&mut self, i: i32, text: String) {
        let i = i as usize;
        let start = self.grid_text.line_to_char(i);
        let end = self.grid_text.line_to_char(i + 1);
        self.grid_text.remove(start..end);
        self.grid_text.insert(start, &text);
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
        self.grid_text = text.into();
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

            if row == self.cursor.y
                && r.start_col <= self.cursor.x as usize
                && self.cursor.x as usize <= r.end_col
            {
                self.draw_cursor();
            }

            if r.attr.undercurl {
                let line_width = r.attr.font_size as f32 * 0.1;
                let desc = r.attr.font.get_descent() as f64;
                let amplitude = desc / 2.0;
                let l = r.len();
                const STEPS_PER_CYCLE: usize = 8;
                let total_span = l * STEPS_PER_CYCLE;
                let mut points = PackedVector2Array::new();
                for i in 0..total_span {
                    let t = i as f64 / total_span as f64;
                    let y = text_position.y as f64
                        + amplitude
                        + -cos(l as f64 * t * TAU) * amplitude as f64;
                    let p = Vector2::new(
                        text_position.x + t as f32 * l as f32 * r.attr.char_size.x,
                        y as f32,
                    );
                    points.push(p);
                }
                self.base_mut()
                    .draw_polyline_ex(&points, r.attr.special)
                    .width(line_width)
                    .done();
            }
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

                let region_text = get_column(&self.grid_text.to_string(), &self.cursor);
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
    }
}

struct Extension;

#[gdextension]
unsafe impl ExtensionLibrary for Extension {}
