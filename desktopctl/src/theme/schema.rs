use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::{Map, Value};
use std::io;

pub const COLOR_FIELD_NAMES: [&str; 24] = [
    "bg",
    "bg_dim",
    "bg1",
    "bg2",
    "bg3",
    "fg",
    "fg2",
    "fg3",
    "fg4",
    "red",
    "green",
    "yellow",
    "blue",
    "purple",
    "cyan",
    "orange",
    "accent",
    "red_bright",
    "green_bright",
    "yellow_bright",
    "blue_bright",
    "purple_bright",
    "cyan_bright",
    "orange_bright",
];

pub const THEME_STATE_FIELD_ORDER: [&str; 25] = [
    "color_scheme",
    "wallpaper",
    "filter_wallpaper",
    "system_font",
    "mono_font",
    "icon_theme",
    "cursor_theme",
    "cursor_size",
    "font_size",
    "mono_font_size",
    "alacritty_mono_font_size_offset",
    "ghostty_mono_font_size_offset",
    "gtk_mono_font_size_offset",
    "neovide_mono_font_size_offset",
    "qt_mono_font_size_offset",
    "vscode_mono_font_size_offset",
    "dark_hint",
    "hypr_gaps_in",
    "hypr_gaps_out",
    "hypr_border_size",
    "hypr_rounding",
    "hypr_blur_enabled",
    "hypr_blur_size",
    "hypr_blur_passes",
    "hypr_animations_enabled",
];

pub const THEME_STATE_STRING_FIELDS: [&str; 6] = [
    "color_scheme",
    "wallpaper",
    "system_font",
    "mono_font",
    "icon_theme",
    "cursor_theme",
];

pub const THEME_STATE_INT_FIELDS: [&str; 15] = [
    "cursor_size",
    "font_size",
    "mono_font_size",
    "alacritty_mono_font_size_offset",
    "ghostty_mono_font_size_offset",
    "gtk_mono_font_size_offset",
    "neovide_mono_font_size_offset",
    "qt_mono_font_size_offset",
    "vscode_mono_font_size_offset",
    "hypr_gaps_in",
    "hypr_gaps_out",
    "hypr_border_size",
    "hypr_rounding",
    "hypr_blur_size",
    "hypr_blur_passes",
];

pub const THEME_STATE_BOOL_FIELDS: [&str; 4] = [
    "filter_wallpaper",
    "dark_hint",
    "hypr_blur_enabled",
    "hypr_animations_enabled",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ColorScheme {
    pub family: String,
    pub variant: String,
    pub bg: String,
    pub bg_dim: String,
    pub bg1: String,
    pub bg2: String,
    pub bg3: String,
    pub fg: String,
    pub fg2: String,
    pub fg3: String,
    pub fg4: String,
    pub red: String,
    pub green: String,
    pub yellow: String,
    pub blue: String,
    pub purple: String,
    pub cyan: String,
    pub orange: String,
    pub accent: String,
    pub red_bright: String,
    pub green_bright: String,
    pub yellow_bright: String,
    pub blue_bright: String,
    pub purple_bright: String,
    pub cyan_bright: String,
    pub orange_bright: String,
    pub palette: [String; 16],
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct NamedColors {
    bg: String,
    bg_dim: String,
    bg1: String,
    bg2: String,
    bg3: String,
    fg: String,
    fg2: String,
    fg3: String,
    fg4: String,
    red: String,
    green: String,
    yellow: String,
    blue: String,
    purple: String,
    cyan: String,
    orange: String,
    accent: String,
    red_bright: String,
    green_bright: String,
    yellow_bright: String,
    blue_bright: String,
    purple_bright: String,
    cyan_bright: String,
    orange_bright: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct ColorSchemeWire {
    family: String,
    variant: String,
    colors: NamedColors,
    palette: [String; 16],
}

impl ColorScheme {
    pub fn known_color_fields() -> &'static [&'static str] {
        &COLOR_FIELD_NAMES
    }
}

impl Serialize for ColorScheme {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let wire = ColorSchemeWire {
            family: self.family.clone(),
            variant: self.variant.clone(),
            colors: NamedColors {
                bg: self.bg.clone(),
                bg_dim: self.bg_dim.clone(),
                bg1: self.bg1.clone(),
                bg2: self.bg2.clone(),
                bg3: self.bg3.clone(),
                fg: self.fg.clone(),
                fg2: self.fg2.clone(),
                fg3: self.fg3.clone(),
                fg4: self.fg4.clone(),
                red: self.red.clone(),
                green: self.green.clone(),
                yellow: self.yellow.clone(),
                blue: self.blue.clone(),
                purple: self.purple.clone(),
                cyan: self.cyan.clone(),
                orange: self.orange.clone(),
                accent: self.accent.clone(),
                red_bright: self.red_bright.clone(),
                green_bright: self.green_bright.clone(),
                yellow_bright: self.yellow_bright.clone(),
                blue_bright: self.blue_bright.clone(),
                purple_bright: self.purple_bright.clone(),
                cyan_bright: self.cyan_bright.clone(),
                orange_bright: self.orange_bright.clone(),
            },
            palette: self.palette.clone(),
        };
        wire.serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for ColorScheme {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let wire = ColorSchemeWire::deserialize(deserializer)?;
        Ok(Self {
            family: wire.family,
            variant: wire.variant,
            bg: wire.colors.bg,
            bg_dim: wire.colors.bg_dim,
            bg1: wire.colors.bg1,
            bg2: wire.colors.bg2,
            bg3: wire.colors.bg3,
            fg: wire.colors.fg,
            fg2: wire.colors.fg2,
            fg3: wire.colors.fg3,
            fg4: wire.colors.fg4,
            red: wire.colors.red,
            green: wire.colors.green,
            yellow: wire.colors.yellow,
            blue: wire.colors.blue,
            purple: wire.colors.purple,
            cyan: wire.colors.cyan,
            orange: wire.colors.orange,
            accent: wire.colors.accent,
            red_bright: wire.colors.red_bright,
            green_bright: wire.colors.green_bright,
            yellow_bright: wire.colors.yellow_bright,
            blue_bright: wire.colors.blue_bright,
            purple_bright: wire.colors.purple_bright,
            cyan_bright: wire.colors.cyan_bright,
            orange_bright: wire.colors.orange_bright,
            palette: wire.palette,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ThemeState {
    pub color_scheme: String,
    pub wallpaper: String,
    pub filter_wallpaper: bool,
    pub system_font: String,
    pub mono_font: String,
    pub icon_theme: String,
    pub cursor_theme: String,
    pub cursor_size: i64,
    pub font_size: i64,
    pub mono_font_size: i64,
    pub alacritty_mono_font_size_offset: i64,
    pub ghostty_mono_font_size_offset: i64,
    pub gtk_mono_font_size_offset: i64,
    pub neovide_mono_font_size_offset: i64,
    pub qt_mono_font_size_offset: i64,
    pub vscode_mono_font_size_offset: i64,
    pub dark_hint: bool,
    pub hypr_gaps_in: i64,
    pub hypr_gaps_out: i64,
    pub hypr_border_size: i64,
    pub hypr_rounding: i64,
    pub hypr_blur_enabled: bool,
    pub hypr_blur_size: i64,
    pub hypr_blur_passes: i64,
    pub hypr_animations_enabled: bool,
    #[serde(default, flatten)]
    pub extra: Map<String, Value>,
}

impl ThemeState {
    pub fn known_field_names() -> &'static [&'static str] {
        &THEME_STATE_FIELD_ORDER
    }

    pub fn string_field_names() -> &'static [&'static str] {
        &THEME_STATE_STRING_FIELDS
    }

    pub fn int_field_names() -> &'static [&'static str] {
        &THEME_STATE_INT_FIELDS
    }

    pub fn bool_field_names() -> &'static [&'static str] {
        &THEME_STATE_BOOL_FIELDS
    }

    pub fn mono_font_size_offset_for(&self, target_name: &str) -> crate::Result<i64> {
        let offset = match target_name {
            "alacritty" => self.alacritty_mono_font_size_offset,
            "ghostty" => self.ghostty_mono_font_size_offset,
            "gtk" => self.gtk_mono_font_size_offset,
            "neovide" => self.neovide_mono_font_size_offset,
            "qt" => self.qt_mono_font_size_offset,
            "vscode" => self.vscode_mono_font_size_offset,
            _ => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("Unknown mono font size target: {target_name}"),
                )
                .into());
            }
        };
        Ok(offset)
    }

    pub fn mono_font_size_for(&self, target_name: &str) -> crate::Result<i64> {
        Ok(self.mono_font_size + self.mono_font_size_offset_for(target_name)?)
    }

    pub fn to_ordered_json_map(&self) -> Map<String, Value> {
        let mut map = Map::new();
        map.insert(
            "color_scheme".to_owned(),
            Value::String(self.color_scheme.clone()),
        );
        map.insert(
            "wallpaper".to_owned(),
            Value::String(self.wallpaper.clone()),
        );
        map.insert(
            "filter_wallpaper".to_owned(),
            Value::Bool(self.filter_wallpaper),
        );
        map.insert(
            "system_font".to_owned(),
            Value::String(self.system_font.clone()),
        );
        map.insert(
            "mono_font".to_owned(),
            Value::String(self.mono_font.clone()),
        );
        map.insert(
            "icon_theme".to_owned(),
            Value::String(self.icon_theme.clone()),
        );
        map.insert(
            "cursor_theme".to_owned(),
            Value::String(self.cursor_theme.clone()),
        );
        map.insert("cursor_size".to_owned(), Value::from(self.cursor_size));
        map.insert("font_size".to_owned(), Value::from(self.font_size));
        map.insert(
            "mono_font_size".to_owned(),
            Value::from(self.mono_font_size),
        );
        map.insert(
            "alacritty_mono_font_size_offset".to_owned(),
            Value::from(self.alacritty_mono_font_size_offset),
        );
        map.insert(
            "ghostty_mono_font_size_offset".to_owned(),
            Value::from(self.ghostty_mono_font_size_offset),
        );
        map.insert(
            "gtk_mono_font_size_offset".to_owned(),
            Value::from(self.gtk_mono_font_size_offset),
        );
        map.insert(
            "neovide_mono_font_size_offset".to_owned(),
            Value::from(self.neovide_mono_font_size_offset),
        );
        map.insert(
            "qt_mono_font_size_offset".to_owned(),
            Value::from(self.qt_mono_font_size_offset),
        );
        map.insert(
            "vscode_mono_font_size_offset".to_owned(),
            Value::from(self.vscode_mono_font_size_offset),
        );
        map.insert("dark_hint".to_owned(), Value::Bool(self.dark_hint));
        map.insert("hypr_gaps_in".to_owned(), Value::from(self.hypr_gaps_in));
        map.insert("hypr_gaps_out".to_owned(), Value::from(self.hypr_gaps_out));
        map.insert(
            "hypr_border_size".to_owned(),
            Value::from(self.hypr_border_size),
        );
        map.insert("hypr_rounding".to_owned(), Value::from(self.hypr_rounding));
        map.insert(
            "hypr_blur_enabled".to_owned(),
            Value::Bool(self.hypr_blur_enabled),
        );
        map.insert(
            "hypr_blur_size".to_owned(),
            Value::from(self.hypr_blur_size),
        );
        map.insert(
            "hypr_blur_passes".to_owned(),
            Value::from(self.hypr_blur_passes),
        );
        map.insert(
            "hypr_animations_enabled".to_owned(),
            Value::Bool(self.hypr_animations_enabled),
        );

        for (key, value) in &self.extra {
            if !map.contains_key(key) {
                map.insert(key.clone(), value.clone());
            }
        }

        map
    }
}
