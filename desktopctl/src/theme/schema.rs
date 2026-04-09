use crate::paths;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::{Map, Value};
use std::{io, path::Path};

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

pub const DEFAULT_COLOR_SCHEME: &str = "gruvbox-dark";
pub const DEFAULT_WALLPAPER_RELATIVE_PATH: &str = "wallpapers/lmao.png";
pub const DEFAULT_FILTER_WALLPAPER: bool = false;
pub const DEFAULT_SYSTEM_FONT: &str = "Overpass";
pub const DEFAULT_MONO_FONT: &str = "JetBrainsMono Nerd Font";
pub const DEFAULT_ICON_THEME: &str = "Neuwaita";
pub const DEFAULT_CURSOR_THEME: &str = "BreezeX-RosePine-Linux";
pub const DEFAULT_CURSOR_SIZE: i64 = 24;
pub const DEFAULT_FONT_SIZE: i64 = 11;
pub const DEFAULT_MONO_FONT_SIZE: i64 = 11;
pub const DEFAULT_ALACRITTY_MONO_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_GHOSTTY_MONO_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_GTK_MONO_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_NEOVIDE_MONO_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_QT_MONO_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_VSCODE_MONO_FONT_SIZE_OFFSET: i64 = 3;
pub const DEFAULT_DARK_HINT: bool = false;
pub const DEFAULT_HYPR_GAPS_IN: i64 = 4;
pub const DEFAULT_HYPR_GAPS_OUT: i64 = 6;
pub const DEFAULT_HYPR_BORDER_SIZE: i64 = 0;
pub const DEFAULT_HYPR_ROUNDING: i64 = 8;
pub const DEFAULT_HYPR_BLUR_ENABLED: bool = false;
pub const DEFAULT_HYPR_BLUR_SIZE: i64 = 3;
pub const DEFAULT_HYPR_BLUR_PASSES: i64 = 4;
pub const DEFAULT_HYPR_ANIMATIONS_ENABLED: bool = true;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ColorSchemeAppearance {
    #[default]
    Light,
    Dark,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct ColorSchemeAppThemes {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bat: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ktexteditor: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub snappy_switcher: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub vicinae: Option<VicinaeThemeNames>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub vscode: Option<VscodeThemeNames>,
}

impl ColorSchemeAppThemes {
    fn is_empty(&self) -> bool {
        self.bat.is_none()
            && self.ktexteditor.is_none()
            && self.snappy_switcher.is_none()
            && self.vicinae.is_none()
            && self.vscode.is_none()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VicinaeThemeNames {
    pub name: String,
    pub light_name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VscodeThemeNames {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extension_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ColorScheme {
    pub family: String,
    pub variant: String,
    pub appearance: ColorSchemeAppearance,
    pub app_themes: ColorSchemeAppThemes,
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
    appearance: ColorSchemeAppearance,
    #[serde(default, skip_serializing_if = "ColorSchemeAppThemes::is_empty")]
    app_themes: ColorSchemeAppThemes,
    colors: NamedColors,
    palette: [String; 16],
}

impl ColorScheme {
    pub fn known_color_fields() -> &'static [&'static str] {
        &COLOR_FIELD_NAMES
    }

    pub fn is_dark(&self) -> bool {
        self.appearance == ColorSchemeAppearance::Dark
    }

    pub fn is_light(&self) -> bool {
        self.appearance == ColorSchemeAppearance::Light
    }

    pub fn bat_theme_name(&self) -> &str {
        self.app_themes.bat.as_deref().unwrap_or("base16")
    }

    pub fn ktexteditor_theme_name(&self) -> &str {
        self.app_themes
            .ktexteditor
            .as_deref()
            .unwrap_or(if self.is_light() {
                "Breeze Light"
            } else {
                "Breeze Dark"
            })
    }

    pub fn snappy_switcher_theme_name(&self) -> &str {
        self.app_themes
            .snappy_switcher
            .as_deref()
            .unwrap_or(if self.is_light() {
                "catppuccin-latte.ini"
            } else {
                "snappy-slate.ini"
            })
    }

    pub fn vicinae_theme_name(&self) -> String {
        self.app_themes
            .vicinae
            .as_ref()
            .map(|themes| themes.name.clone())
            .unwrap_or_else(|| format!("{}-{}", self.family, self.variant))
    }

    pub fn vicinae_light_theme_name(&self) -> String {
        self.app_themes
            .vicinae
            .as_ref()
            .map(|themes| themes.light_name.clone())
            .unwrap_or_else(|| self.vicinae_theme_name())
    }

    pub fn vscode_theme_name(&self) -> String {
        self.app_themes
            .vscode
            .as_ref()
            .map(|themes| themes.name.clone())
            .unwrap_or_else(|| format!("{}-{}", self.family, self.variant))
    }

    pub fn vscode_extension_id(&self) -> Option<&str> {
        self.app_themes
            .vscode
            .as_ref()
            .and_then(|themes| themes.extension_id.as_deref())
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
            appearance: self.appearance,
            app_themes: self.app_themes.clone(),
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
            appearance: wire.appearance,
            app_themes: wire.app_themes,
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
    pub fn default_state() -> crate::Result<Self> {
        Ok(Self::default_state_for_repo_root(&paths::repo_root()?))
    }

    pub fn default_state_for_repo_root(repo_root: &Path) -> Self {
        let default_dark_hint = crate::theme::resolve::load_colors(
            DEFAULT_COLOR_SCHEME,
            &repo_root.join("themes/colors"),
        )
        .map(|colors| colors.is_dark())
        .unwrap_or(DEFAULT_DARK_HINT);
        Self {
            color_scheme: DEFAULT_COLOR_SCHEME.to_owned(),
            wallpaper: repo_root
                .join(DEFAULT_WALLPAPER_RELATIVE_PATH)
                .display()
                .to_string(),
            filter_wallpaper: DEFAULT_FILTER_WALLPAPER,
            system_font: DEFAULT_SYSTEM_FONT.to_owned(),
            mono_font: DEFAULT_MONO_FONT.to_owned(),
            icon_theme: DEFAULT_ICON_THEME.to_owned(),
            cursor_theme: DEFAULT_CURSOR_THEME.to_owned(),
            cursor_size: DEFAULT_CURSOR_SIZE,
            font_size: DEFAULT_FONT_SIZE,
            mono_font_size: DEFAULT_MONO_FONT_SIZE,
            alacritty_mono_font_size_offset: DEFAULT_ALACRITTY_MONO_FONT_SIZE_OFFSET,
            ghostty_mono_font_size_offset: DEFAULT_GHOSTTY_MONO_FONT_SIZE_OFFSET,
            gtk_mono_font_size_offset: DEFAULT_GTK_MONO_FONT_SIZE_OFFSET,
            neovide_mono_font_size_offset: DEFAULT_NEOVIDE_MONO_FONT_SIZE_OFFSET,
            qt_mono_font_size_offset: DEFAULT_QT_MONO_FONT_SIZE_OFFSET,
            vscode_mono_font_size_offset: DEFAULT_VSCODE_MONO_FONT_SIZE_OFFSET,
            dark_hint: default_dark_hint,
            hypr_gaps_in: DEFAULT_HYPR_GAPS_IN,
            hypr_gaps_out: DEFAULT_HYPR_GAPS_OUT,
            hypr_border_size: DEFAULT_HYPR_BORDER_SIZE,
            hypr_rounding: DEFAULT_HYPR_ROUNDING,
            hypr_blur_enabled: DEFAULT_HYPR_BLUR_ENABLED,
            hypr_blur_size: DEFAULT_HYPR_BLUR_SIZE,
            hypr_blur_passes: DEFAULT_HYPR_BLUR_PASSES,
            hypr_animations_enabled: DEFAULT_HYPR_ANIMATIONS_ENABLED,
            extra: Map::new(),
        }
    }

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
