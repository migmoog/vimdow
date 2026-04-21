use godot::classes::{Control, Font, FontVariation, IControl};
use godot::prelude::*;
use itertools::Itertools;

/// Creates rendering data based on the hl attributes
/// defined by neovim. Returns structs applied with the appropriate theme
#[derive(GodotClass)]
#[class(tool, init, base = Control)]
pub struct Highlighter {
    base: Base<Control>,

    #[export]
    #[var(pub)]
    hl_data: VarDictionary,

    #[export]
    #[var(pub)]
    hl_regions: Array<PackedInt32Array>,

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
        self.reload_fonts();

        self.signals()
            .theme_changed()
            .connect_self(Self::reload_fonts);
    }
}

impl Highlighter {
    fn reload_fonts(&mut self) {
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
    pub special: Color,
    pub font: Gd<FontVariation>,
    pub undercurl: bool,
    pub underline: bool,
    pub underdouble: bool,
    pub underdotted: bool,
    pub underdashed: bool,
    pub strikethrough: bool,
    pub url: bool,
    pub font_size: i32,
    pub char_size: Vector2,
}

pub struct Region {
    pub start_col: usize,
    pub end_col: usize,
    pub attr: HlAttr,
}
impl Region {
    pub fn len(&self) -> usize {
        self.end_col - self.start_col
    }
}

type VD = VarDictionary;
#[godot_api]
impl Highlighter {
    // check ":h ui-event-hl_attr_define"
    pub fn get_hl_attr(&self, hl_id: i32) -> HlAttr {
        let attr: VD = self.hl_data.at(hl_id).to();
        let font = if attr.contains_key("bold") {
            &self.bold_font
        } else if attr.contains_key("italic") {
            &self.italic_font
        } else {
            &self.normal_font
        }
        .clone();

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

        let mut special = match self.get_attr_color(hl_id, HlAttrColor::Special) {
            Ok(fg) => fg,
            Err(bg) => bg,
        };

        if let Some(blend_pct) = attr
            .get("blend")
            .map(|i| (100.0 - i.to::<i32>() as f32) / 100.0)
        {
            foreground.a = blend_pct;
            background.a = blend_pct;
            special.a = blend_pct;
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

        let undercurl = attr.contains_key("undercurl");

        HlAttr {
            foreground,
            background,
            special,
            font,
            undercurl,
            underline: attr.contains_key("underline"),
            underdouble: attr.contains_key("underdouble"),
            underdotted: attr.contains_key("underdotted"),
            underdashed: attr.contains_key("underdashed"),
            strikethrough: attr.contains_key("strikethrough"),
            url: attr.contains_key("strikethrough"),
            font_size,
            char_size,
        }
    }

    fn get_default_color(&self, c: HlAttrColor) -> Color {
        self.hl_data.at(0).to::<VD>().at(c.to_string()).to()
    }

    fn get_attr_color(&self, hl_id: i32, c: HlAttrColor) -> Result<Color, Color> {
        self.hl_data
            .at(hl_id)
            .to::<VD>()
            .get(c.to_string())
            .map(|rgb| rgb.to())
            .ok_or_else(|| self.get_default_color(c))
    }

    #[func]
    pub fn clear(&mut self) {
        // self.hl_regions.clear();
        for y in 0..self.hl_regions.len() {
            self.hl_regions.at(y).fill(0);
        }
    }

    pub fn get_regions(&self, row: i32) -> Vec<Region> {
        let Some(row_regions) = self.hl_regions.get(row as usize) else {
            return vec![];
        };

        row_regions
            .as_slice()
            .iter()
            .map(|&n| n as i32)
            .enumerate()
            .chunk_by(|(_, hl_id)| *hl_id)
            .into_iter()
            .map(|(hl_id, mut chunk)| {
                let (start_col, _) = chunk.next().unwrap();
                let end_col = chunk.last().map(|(i, _)| i + 1).unwrap_or(start_col + 1);
                Region {
                    start_col,
                    end_col,
                    attr: self.get_hl_attr(hl_id),
                }
            })
            .collect()
    }

    pub fn get_cursor_attr(&self, cursor: &Vector2i) -> HlAttr {
        let cursor_hl_id = self.hl_regions.at(cursor.y as usize)[cursor.x as usize];
        self.get_hl_attr(cursor_hl_id as i32)
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
