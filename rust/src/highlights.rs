use godot::classes::{Control, Font, FontVariation, IControl};
use godot::prelude::*;

use crate::neovim::rgb_to_color;

/// Creates rendering data based on the hl attributes
/// defined by neovim. Returns structs applied with the appropriate theme
#[derive(GodotClass)]
#[class(init, base = Control)]
pub struct Highlighter {
    base: Base<Control>,

    #[export]
    hl_data: VarDictionary,

    #[export]
    hl_regions: VarDictionary,

    bold_font: Gd<FontVariation>,
    italic_font: Gd<FontVariation>,
    normal_font: Gd<FontVariation>,
}

const THEME_TYPE: &'static str = "VimdowEditor";

// wraps a font in a font variation
fn fv(font: &Gd<Font>) -> Gd<FontVariation> {
    let mut out = FontVariation::new_gd();
    out.set_base_font(font);
    out
}

#[godot_api]
impl IControl for Highlighter {
    fn ready(&mut self) {
        self.normal_font = self
            .base()
            .get_theme_font_ex("normal")
            .theme_type(THEME_TYPE)
            .done()
            .as_ref()
            .map(fv)
            .expect("Must have a default normal font for vimdow to work");

        self.bold_font = self
            .base()
            .get_theme_font_ex("bold")
            .theme_type(THEME_TYPE)
            .done()
            .as_ref()
            .map(fv)
            .unwrap_or_else(|| {
                let mut out = self.normal_font.clone();
                out.set_variation_embolden(0.5);
                out
            });

        self.italic_font = self
            .base()
            .get_theme_font_ex("italic")
            .theme_type(THEME_TYPE)
            .done()
            .as_ref()
            .map(fv)
            .unwrap_or_else(|| {
                let mut out = self.normal_font.clone();
                let mut transform = out.get_variation_transform();
                transform.a.y = 0.2;
                out.set_variation_transform(transform);
                out
            });
    }
}

pub struct HlAttr {
    pub foreground: Color,
    pub background: Color,
    pub font: Gd<FontVariation>,
    pub font_size: i32,
    pub char_size: Vector2,
}

pub struct Region {
    pub start_col: usize,
    pub end_col: usize,
    pub attr: HlAttr,
}

type VD = VarDictionary;
#[godot_api]
impl Highlighter {
    // check ":h ui-event-hl_attr_define"
    fn get_hl_attr(&self, hl_id: i32) -> HlAttr {
        let attr: VD = self.hl_data.at(hl_id).to();
        let font = if attr.contains_key("bold") {
            &self.bold_font
        } else if attr.contains_key("italic") {
            &self.italic_font
        } else {
            &self.normal_font
        }.clone();

        let (mut foreground, mut background) = (
            match self.get_attr_color(hl_id, HlAttrColor::Foreground) {
                Ok(fg) => fg,
                Err(bg) => bg,
            },
            match self.get_attr_color(hl_id, HlAttrColor::Background) {
                Ok(fg) => fg,
                Err(bg) => bg,
            },
        );

        if attr.contains_key("reverse") {
            (foreground, background) = (background, foreground);
        }

        let font_size = self
            .base()
            .get_theme_font_size_ex("font_size")
            .theme_type(THEME_TYPE)
            .done();

        let char_size = font
            .get_base_font()
            .unwrap()
            .get_char_size(' ' as u32, font_size);

        HlAttr {
            foreground,
            background,
            font,
            font_size,
            char_size,
        }
    }

    fn get_default_color(&self, c: HlAttrColor) -> Color {
        rgb_to_color(self.hl_data.at(0).to::<VD>().at(c.to_string()).to())
    }

    fn get_attr_color(&self, hl_id: i32, c: HlAttrColor) -> Result<Color, Color> {
        self.hl_data
            .at(hl_id)
            .to::<VD>()
            .get(c.to_string())
            .map(|rgb| rgb_to_color(rgb.to()))
            .ok_or_else(|| self.get_default_color(c))
    }

    #[func]
    pub fn clear(&mut self) {
        self.hl_regions.clear();
    }

    pub fn get_regions(&self, row: i32, line_len: usize) -> Vec<Region> {
        let mut out = vec![];
        if let Some(reg) = self.hl_regions.get(row) {
            let reg = reg.to::<VD>();
            let mut reg_iter = reg.iter_shared().peekable();
            while let Some((current_col, hl_id)) = reg_iter.next() {
                let (current_col, hl_id) = (current_col.to::<i32>() as usize, hl_id.to::<i32>());
                let next_col = reg_iter
                    .peek()
                    .map(|(next_col, _)| next_col.to::<i32>() as usize)
                    .unwrap_or(line_len);

                assert!(
                    current_col <= next_col,
                    "current: {}, next: {}",
                    current_col,
                    next_col
                );

                out.push(Region {
                    start_col: current_col,
                    end_col: next_col,
                    attr: self.get_hl_attr(hl_id),
                });
            }
        }

        out
    }

    pub fn get_cursor_attr(&self, cursor: &Vector2i) -> HlAttr {
        let mut closest_col = -1;
        let mut out_hl_id = 0;
        for (col, hl_id) in self
            .hl_regions
            .get(cursor.y)
            .unwrap_or_else(|| self.hl_data.at(0))
            .to::<VD>()
            .iter_shared()
        {
            let (col, hl_id) = (col.to::<i32>(), hl_id.to::<i32>());
            if col > closest_col && col <= cursor.x {
                closest_col = col;
                out_hl_id = hl_id;
            }
        }

        self.get_hl_attr(out_hl_id)
    }
}

// choices of default color to pick
enum HlAttrColor {
    Foreground,
    Background,
    Special,
}

impl ToString for HlAttrColor {
    fn to_string(&self) -> String {
        match self {
            Self::Foreground => "foreground",
            Self::Background => "background",
            Self::Special => "special",
        }
        .into()
    }
}
