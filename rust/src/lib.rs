use std::collections::HashMap;

use godot::{
    classes::{Control, Font, FontVariation, IControl, ProjectSettings},
    obj::WithBaseField,
    prelude::*,
};

mod err;
mod neovim;

use indexmap::IndexMap;
pub use neovim::NeovimClient;
use neovim::{Window, rgb_to_color};
use unicode_segmentation::UnicodeSegmentation;

struct Region {
    start_col: usize,
    end_col: usize,
    foreground: Color,
    background: Color,
    font: Gd<FontVariation>,
    font_size: i32,
    char_size: Vector2,
}

fn column_slice(row: &str, start: usize, end: usize) -> String {
    assert!(start <= end);
    row.graphemes(true).skip(start).take(end - start).collect()
}

fn column_replace(destination: &str, source: &str, start: usize, end: usize) -> String {
    let source_graphemes = source.graphemes(true).collect::<Vec<_>>();
    destination
        .graphemes(true)
        .enumerate()
        .map(|(index, grapheme)| {
            if index >= start && index < end {
                source_graphemes[index - start]
            } else {
                grapheme
            }
        })
        .collect()
}

// choices of default color to pick
enum DefaultColor {
    Foreground,
    Background,
    Special,
}

impl ToString for DefaultColor {
    fn to_string(&self) -> String {
        match self {
            Self::Foreground => "foreground",
            Self::Background => "background",
            Self::Special => "special",
        }
        .into()
    }
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

    #[init(val = Vector2i {x: -1, y: -1})]
    #[var]
    cursor: Vector2i,

    #[export]
    hl_data: VarDictionary,
    // { [row]: { [col]: hl_id }}
    hl_regions: HashMap<i32, IndexMap<i32, i32>>,

    #[export]
    current_mode: VarDictionary,
}

#[godot_api]
impl VimdowWindow {
    #[func]
    fn insert_hl_column(&mut self, row: i32, column: i32, hl_id: i32) {
        self.hl_regions
            .entry(row)
            .and_modify(|cols| {
                cols.insert_sorted(column, hl_id);
            })
            .or_insert_with(|| <_>::from([(column, hl_id)]));
    }

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

    fn get_font_and_size(&self) -> (Gd<Font>, i32) {
        let font = self
            .base()
            .get_theme_font_ex("normal")
            .theme_type("VimdowEditor")
            .done()
            .expect("Should have a font");
        let font_size = self
            .base()
            .get_theme_font_size_ex("font_size")
            .theme_type("VimdowEditor")
            .done();
        (font, font_size)
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
    fn scroll(&mut self, top: i32, bot: i32, left: i32, right: i32, rows: i32) {
        // let mut lines = (top..bot).map(|i| self.get_line(i)).collect::<Vec<_>>();
        let mut lines = Vec::new();
        let mut hls = Vec::new();
        for i in top..bot {
            lines.push(self.get_line(i));
            // if let Some(region) = self.hl_regions.remove(&i) {
            //     hls.insert(i, region);
            // }
            hls.push(self.hl_regions.remove(&i));
        }

        let (dst_top, dst_bot) = (top - rows, bot - rows);
        for i in dst_top..dst_bot {
            let source_line = lines.remove(0);
            let source_region = hls.remove(0);
            if i < top || i >= bot {
                continue;
            }
            let destination_line = self.get_line(i);
            let (start, end) = (left as usize, right as usize);
            self.set_line(
                i,
                column_replace(&destination_line, &source_line, start, end),
            );
            if let Some(source_region) = source_region {
                self.hl_regions.insert(i, source_region);
            }
        }
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

        self.hl_regions.clear();
    }

    #[func]
    fn clear_hl_region(&mut self, row: i32, start: i32, end: i32) {
        if let Some(columns) = self.hl_regions.get_mut(&row) {
            // NOTE: optimizable
            for i in start..end {
                columns.shift_remove(&i);
            }
        }
    }

    #[func]
    // starts a redraw with the provided highlight data
    fn flush(&mut self, hl: VarDictionary, current_mode: VarDictionary) {
        self.hl_data = hl;
        self.current_mode = current_mode;
        self.base_mut().queue_redraw();
    }

    fn get_hl_default_color(&self, choice: DefaultColor) -> Color {
        self.hl_data
            .at(0)
            .to::<VarDictionary>()
            .get(choice.to_string())
            .map(|v| rgb_to_color(v.to()))
            .expect("Should have a default color of this type")
    }

    fn get_hl_regions(&self, row: i32) -> Vec<Region> {
        let (font, font_size) = self.get_font_and_size();
        let char_size = font.get_char_size(' ' as u32, font_size);
        let line = self.get_line(row);
        let mut regions = vec![];

        let default_fg = self.get_hl_default_color(DefaultColor::Foreground);
        let default_bg = self.get_hl_default_color(DefaultColor::Background);
        if let Some(region) = self.hl_regions.get(&row) {
            let mut region_iter = region.iter().peekable();
            while let Some((&current_col, &hl_id)) = region_iter.next() {
                let hl: VarDictionary = self.hl_data.at(hl_id).to();
                let next_col = region_iter
                    .peek()
                    .map(|&(&next_col, _)| next_col)
                    .unwrap_or_else(|| line.len() as i32);
                assert!(
                    current_col <= next_col,
                    "current: {}, next: {}",
                    current_col,
                    next_col
                );

                let mut foreground: Color = hl
                    .get("foreground")
                    .map(|d| rgb_to_color(d.to()))
                    .unwrap_or(default_fg);
                let mut background: Color = hl
                    .get("background")
                    .map(|d| rgb_to_color(d.to()))
                    .unwrap_or(default_bg);

                if hl.get("reverse").is_some() {
                    (foreground, background) = (background, foreground);
                }

                let mut region_font = FontVariation::new_gd();
                if hl.get("bold").is_some() {
                    if let Some(bold_font) = self
                        .base()
                        .get_theme_font_ex("bold")
                        .theme_type("VimdowEditor")
                        .done()
                    {
                        region_font.set_base_font(&bold_font);
                    } else {
                        region_font.set_base_font(&font);
                        region_font.set_variation_embolden(1.0);
                    }
                } else {
                    region_font.set_base_font(&font);
                }

                if hl.get("italic").is_some() {
                    let mut transform = region_font.get_variation_transform();
                    transform.a.y = 0.2;
                    region_font.set_variation_transform(transform);
                }

                regions.push(Region {
                    start_col: current_col as usize,
                    end_col: next_col as usize,
                    foreground,
                    background,
                    font: region_font,
                    char_size,
                    font_size,
                });
            }
        } else {
            regions.push(Region {
                start_col: 0,
                end_col: line.len(),
                foreground: self.get_hl_default_color(DefaultColor::Foreground),
                background: self.get_hl_default_color(DefaultColor::Background),
                font: {
                    let mut out = FontVariation::new_gd();
                    out.set_base_font(&font);
                    out
                },
                char_size,
                font_size,
            });
        }

        regions
    }

    fn draw_row(&mut self, row: i32) {
        let ignore_hl: bool = ProjectSettings::singleton()
            .get_setting("vimdow/debug/ignore_hl")
            .try_to()
            .unwrap_or(false);

        let regions = self.get_hl_regions(row);

        if !ignore_hl {
            // drawing background colors
            for r in regions.iter() {
                let position = Vector2 {
                    x: r.char_size.x * r.start_col as f32,
                    y: r.char_size.y * row as f32,
                };
                let size = Vector2 {
                    x: r.char_size.x * (r.end_col - r.start_col) as f32,
                    y: r.char_size.y,
                };

                // drawing colored background
                self.base_mut()
                    .draw_rect_ex(Rect2 { position, size }, r.background)
                    .filled(true)
                    .done();
            }
        }

        // drawing text with foreground colors
        let default_fg = self.get_hl_default_color(DefaultColor::Foreground);
        for r in regions.iter() {
            let text_position = Vector2 {
                x: r.start_col as f32 * r.char_size.x,
                y: row as f32 * r.char_size.y
                    + r.font.get_ascent_ex().font_size(r.font_size).done(),
            };

            let region_text = column_slice(&self.get_line(row), r.start_col, r.end_col);

            self.base_mut()
                .draw_string_ex(&r.font, text_position, &region_text)
                .font_size(r.font_size)
                .modulate(if ignore_hl { default_fg } else { r.foreground })
                .done();
        }
    }

    fn draw_cursor(&mut self) {
        let cursor_col = self.cursor.x as usize;
        let cell_region = self
            .get_hl_regions(self.cursor.y)
            .into_iter()
            .find(|r| r.start_col <= cursor_col && cursor_col <= r.end_col)
            .expect("Cursor shouldn't be drawn if it isn't visible on the screen");

        let position =
            { Vector2::new(self.cursor.x as f32, self.cursor.y as f32) * cell_region.char_size };
        let cs = cell_region.char_size;
        match self.current_mode.at("cursor_shape").to_string().as_str() {
            "block" => {
                self.base_mut()
                    .draw_rect_ex(Rect2 { position, size: cs }, cell_region.foreground)
                    .filled(true)
                    .done();

                let row = self.cursor.y;
                let line = self.get_line(row);
                self.base_mut()
                    .draw_string_ex(
                        &cell_region.font,
                        Vector2 {
                            x: position.x,
                            y: position.y + cell_region.font.get_ascent(),
                        },
                        &column_slice(&line, cursor_col, cursor_col + 1),
                    )
                    .font_size(cell_region.font_size)
                    .modulate(cell_region.background)
                    .done()
            }
            "vertical" => {
                self.base_mut().draw_line(
                    position,
                    Vector2 {
                        x: position.x,
                        y: position.y + cs.y,
                    },
                    cell_region.foreground,
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
                    cell_region.foreground,
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
