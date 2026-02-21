use std::collections::HashMap;

use godot::{
    classes::{Control, Font, FontVariation, IControl},
    obj::WithBaseField,
    prelude::*,
};

mod err;
mod neovim;

use indexmap::IndexMap;
pub use neovim::NeovimClient;
use neovim::{Window, rgb_to_color};

#[derive(GodotConvert, Var, Export, Default)]
#[godot(via = GString)]
#[allow(non_camel_case_types)]
enum CursorShape {
    #[default]
    block,
    vertical,
    horizontal,
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

    #[export]
    cursor_shape: CursorShape,

    #[init(val = Vector2i {x: -1, y: -1})]
    #[var]
    cursor: Vector2i,

    #[export]
    hl_data: VarDictionary,
    // { [row]: { [col]: hl_id }}
    hl_regions: HashMap<i32, IndexMap<i32, i32>>,
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
            .unwrap()
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
    fn flush(&mut self, hl: VarDictionary) {
        self.hl_data = hl;
        self.base_mut().queue_redraw();
    }

    fn get_hl_default_color(&self, choice: DefaultColor) -> Color {
        self.hl_data
            .get(choice.to_string())
            .map(|v| rgb_to_color(v.to()))
            .expect("Should have a default color of this type")
    }

    fn draw_row(&mut self, row: i32) {
        let (font, font_size) = self.get_font_and_size();
        let char_size = font.get_char_size(' '.into(), font_size);
        let line = self.get_line(row);

        struct Region {
            start_col: usize,
            end_col: usize,
            foreground: Color,
            background: Color,
            font: Gd<FontVariation>,
        }
        let mut regions = vec![];

        let default_hl: VarDictionary = self.hl_data.at(0).to();
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
                    .unwrap_or_else(|| rgb_to_color(default_hl.at("foreground").to()));
                let mut background: Color = hl
                    .get("background")
                    .map(|d| rgb_to_color(d.to()))
                    .unwrap_or_else(|| rgb_to_color(default_hl.at("background").to()));

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
            });
        }

        // drawing background colors
        for r in regions.iter() {
            let sl = &line[r.start_col..r.end_col];
            let position = Vector2 {
                x: char_size.x * r.start_col as f32,
                y: char_size.y * row as f32,
            };
            let size = Vector2 {
                x: char_size.x * sl.len() as f32,
                y: char_size.y,
            };

            // drawing colored background
            self.base_mut()
                .draw_rect_ex(Rect2 { position, size }, r.background)
                .filled(true)
                .done();
        }

        // drawing text with foreground colors
        for r in regions.iter() {
            let text_position = Vector2 {
                x: r.start_col as f32 * char_size.x,
                y: row as f32 * char_size.y + font.get_ascent_ex().font_size(font_size).done(),
            };
            self.base_mut()
                .draw_string_ex(&r.font, text_position, &line[r.start_col..r.end_col])
                .font_size(font_size)
                .modulate(r.foreground)
                .done();
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
