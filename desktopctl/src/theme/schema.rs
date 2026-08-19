use crate::paths;
use serde::{Deserialize, Deserializer, Serialize, Serializer, de};
use serde_json::{Map, Value};
use std::{borrow::Cow, io, path::Path};

/// Colors a scheme file must author. The dimmed foreground ramp is absent on
/// purpose: it is derived by [`dim_ramp`], not transcribed.
pub const COLOR_FIELD_NAMES: [&str; 21] = [
    "bg",
    "bg_dim",
    "bg1",
    "bg2",
    "bg3",
    "fg",
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

pub const THEME_STATE_FIELD_ORDER: [&str; 30] = [
    "color_scheme",
    "wallpaper",
    "wallpaper_dir",
    "filter_wallpaper",
    "system_font",
    "mono_font",
    "icon_theme",
    "cursor_theme",
    "cursor_size",
    "font_size",
    "quickshell_font_size_offset",
    "gtk_font_size_offset",
    "qt_font_size_offset",
    "mono_font_size",
    "alacritty_mono_font_size_offset",
    "ghostty_mono_font_size_offset",
    "gtk_mono_font_size_offset",
    "neovide_mono_font_size_offset",
    "qt_mono_font_size_offset",
    "vscode_mono_font_size_offset",
    "zed_mono_font_size_offset",
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

pub const THEME_STATE_STRING_FIELDS: [&str; 7] = [
    "color_scheme",
    "wallpaper",
    "wallpaper_dir",
    "system_font",
    "mono_font",
    "icon_theme",
    "cursor_theme",
];

pub const THEME_STATE_INT_FIELDS: [&str; 19] = [
    "cursor_size",
    "font_size",
    "quickshell_font_size_offset",
    "gtk_font_size_offset",
    "qt_font_size_offset",
    "mono_font_size",
    "alacritty_mono_font_size_offset",
    "ghostty_mono_font_size_offset",
    "gtk_mono_font_size_offset",
    "neovide_mono_font_size_offset",
    "qt_mono_font_size_offset",
    "vscode_mono_font_size_offset",
    "zed_mono_font_size_offset",
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
pub const DEFAULT_WALLPAPER_RELATIVE_PATH: &str = "styling/wallpapers/lmao.png";
/// Directory the wallpaper picker browses. Held separately from `wallpaper` so
/// that browsing to a directory survives without also selecting a wallpaper
/// from it — deriving it from the current wallpaper's parent loses the choice
/// as soon as the picker closes. No target consumes it.
pub const DEFAULT_WALLPAPER_DIR_RELATIVE_PATH: &str = "styling/wallpapers";
pub const DEFAULT_FILTER_WALLPAPER: bool = false;
pub const DEFAULT_SYSTEM_FONT: &str = "Overpass";
pub const DEFAULT_MONO_FONT: &str = "JetBrainsMono Nerd Font";
pub const DEFAULT_ICON_THEME: &str = "Neuwaita";
pub const DEFAULT_CURSOR_THEME: &str = "BreezeX-RosePine-Linux";
pub const DEFAULT_CURSOR_SIZE: i64 = 24;
pub const DEFAULT_FONT_SIZE: i64 = 11;
pub const DEFAULT_QUICKSHELL_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_GTK_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_QT_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_MONO_FONT_SIZE: i64 = 11;
pub const DEFAULT_ALACRITTY_MONO_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_GHOSTTY_MONO_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_GTK_MONO_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_NEOVIDE_MONO_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_QT_MONO_FONT_SIZE_OFFSET: i64 = 0;
pub const DEFAULT_VSCODE_MONO_FONT_SIZE_OFFSET: i64 = 3;
pub const DEFAULT_ZED_MONO_FONT_SIZE_OFFSET: i64 = 4;
pub const DEFAULT_DARK_HINT: bool = false;
pub const DEFAULT_HYPR_GAPS_IN: i64 = 4;
pub const DEFAULT_HYPR_GAPS_OUT: i64 = 6;
pub const DEFAULT_HYPR_BORDER_SIZE: i64 = 0;
pub const DEFAULT_HYPR_ROUNDING: i64 = 8;
pub const DEFAULT_HYPR_BLUR_ENABLED: bool = true;
pub const DEFAULT_HYPR_BLUR_SIZE: i64 = 8;
pub const DEFAULT_HYPR_BLUR_PASSES: i64 = 3;
pub const DEFAULT_HYPR_ANIMATIONS_ENABLED: bool = true;

pub fn canonicalize_theme_string_value<'a>(key: &str, value: &'a str) -> Cow<'a, str> {
    match (key, value) {
        ("mono_font", "JetBrains Mono Nerd Font") => Cow::Borrowed("JetBrainsMono Nerd Font"),
        ("mono_font", "Fira Code Nerd Font") => Cow::Borrowed("FiraCode Nerd Font"),
        ("mono_font", "Commit Mono") => Cow::Borrowed("CommitMono"),
        _ => Cow::Borrowed(value),
    }
}

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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub zed: Option<String>,
}

impl ColorSchemeAppThemes {
    fn is_empty(&self) -> bool {
        self.bat.is_none()
            && self.ktexteditor.is_none()
            && self.snappy_switcher.is_none()
            && self.vicinae.is_none()
            && self.vscode.is_none()
            && self.zed.is_none()
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
    /// File icon theme id contributed by an extension — note this is the icon
    /// theme's own id (`catppuccin-mocha`), not the extension id. Schemes that
    /// have no matching icon set leave it unset and get the neutral fallback
    /// tinted with the scheme accent.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub icon_theme: Option<String>,
}

/// Fractions of the way from `fg` toward `bg` for each dimmed step. Fitted to
/// the schemes whose hand-transcribed ramps were already ordered correctly, so
/// those barely move; the ordering itself is guaranteed by the fractions being
/// strictly increasing.
const DIM_RAMP_STEPS: [f64; 4] = [0.15, 0.30, 0.42, 0.70];

pub struct DimRamp {
    pub fg2: String,
    pub fg3: String,
    pub fg4: String,
    pub fg_faint: String,
}

/// Derive the dimmed foreground ramp by blending `fg` toward `bg`.
///
/// Upstream palettes disagree about what their secondary foreground slots mean
/// — Solarized's `base1` is *emphasized* text and Nord's `nord5` is brighter
/// than `nord4` — so transcribing them left four schemes rendering secondary
/// text more prominent than primary. Blending removes the question: prominence
/// falls monotonically because the blend fraction rises monotonically.
pub fn dim_ramp(fg: &str, bg: &str) -> Result<DimRamp, String> {
    let fg = parse_hex(fg)?;
    let bg = parse_hex(bg)?;
    let mut steps = DIM_RAMP_STEPS
        .iter()
        .map(|fraction| blend(fg, bg, *fraction));

    Ok(DimRamp {
        fg2: steps.next().expect("ramp step"),
        fg3: steps.next().expect("ramp step"),
        fg4: steps.next().expect("ramp step"),
        fg_faint: steps.next().expect("ramp step"),
    })
}

fn parse_hex(value: &str) -> Result<[u8; 3], String> {
    let digits = value.strip_prefix('#').unwrap_or(value);
    if digits.len() != 6 {
        return Err(format!("expected a #rrggbb color, got '{value}'"));
    }

    let mut channels = [0_u8; 3];
    for (index, channel) in channels.iter_mut().enumerate() {
        let start = index * 2;
        *channel = u8::from_str_radix(&digits[start..start + 2], 16)
            .map_err(|_| format!("expected a #rrggbb color, got '{value}'"))?;
    }
    Ok(channels)
}

fn blend(from: [u8; 3], to: [u8; 3], fraction: f64) -> String {
    let channel = |index: usize| {
        let from = f64::from(from[index]);
        (from + (f64::from(to[index]) - from) * fraction).round() as u8
    };
    format!("#{:02x}{:02x}{:02x}", channel(0), channel(1), channel(2))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ColorScheme {
    pub family: String,
    pub variant: String,
    pub appearance: ColorSchemeAppearance,
    /// Same-family scheme to pair with when a dark appearance is requested
    /// (set on light schemes, e.g. catppuccin-latte -> catppuccin-mocha).
    pub dark_scheme: Option<String>,
    pub app_themes: ColorSchemeAppThemes,
    pub bg: String,
    pub bg_dim: String,
    pub bg1: String,
    pub bg2: String,
    pub bg3: String,
    pub fg: String,
    /// Dimmed foreground ramp, derived from `fg` and `bg` by [`dim_ramp`] rather
    /// than transcribed per scheme, so prominence always decreases fg > fg2 >
    /// fg3 > fg4 > fg_faint no matter what an upstream palette calls its slots.
    pub fg2: String,
    pub fg3: String,
    pub fg4: String,
    pub fg_faint: String,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    dark_scheme: Option<String>,
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

    /// Neutral icon set used by every scheme that ships no matching one. It
    /// takes a folder color, so the fallback still tracks the active scheme.
    pub const FALLBACK_VSCODE_ICON_THEME: &'static str = "material-icon-theme";

    pub fn vscode_icon_theme(&self) -> &str {
        self.app_themes
            .vscode
            .as_ref()
            .and_then(|themes| themes.icon_theme.as_deref())
            .unwrap_or(Self::FALLBACK_VSCODE_ICON_THEME)
    }

    pub fn vscode_extension_id(&self) -> Option<&str> {
        self.app_themes
            .vscode
            .as_ref()
            .and_then(|themes| themes.extension_id.as_deref())
    }

    pub fn zed_theme_name(&self) -> String {
        self.app_themes
            .zed
            .clone()
            .unwrap_or_else(|| format!("{}-{}", self.family, self.variant))
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
            dark_scheme: self.dark_scheme.clone(),
            app_themes: self.app_themes.clone(),
            colors: NamedColors {
                bg: self.bg.clone(),
                bg_dim: self.bg_dim.clone(),
                bg1: self.bg1.clone(),
                bg2: self.bg2.clone(),
                bg3: self.bg3.clone(),
                fg: self.fg.clone(),
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
        let ramp = dim_ramp(&wire.colors.fg, &wire.colors.bg).map_err(de::Error::custom)?;
        Ok(Self {
            family: wire.family,
            variant: wire.variant,
            appearance: wire.appearance,
            dark_scheme: wire.dark_scheme,
            app_themes: wire.app_themes,
            bg: wire.colors.bg,
            bg_dim: wire.colors.bg_dim,
            bg1: wire.colors.bg1,
            bg2: wire.colors.bg2,
            bg3: wire.colors.bg3,
            fg2: ramp.fg2,
            fg3: ramp.fg3,
            fg4: ramp.fg4,
            fg_faint: ramp.fg_faint,
            fg: wire.colors.fg,
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
    pub wallpaper_dir: String,
    pub filter_wallpaper: bool,
    pub system_font: String,
    pub mono_font: String,
    pub icon_theme: String,
    pub cursor_theme: String,
    pub cursor_size: i64,
    pub font_size: i64,
    pub quickshell_font_size_offset: i64,
    pub gtk_font_size_offset: i64,
    pub qt_font_size_offset: i64,
    pub mono_font_size: i64,
    pub alacritty_mono_font_size_offset: i64,
    pub ghostty_mono_font_size_offset: i64,
    pub gtk_mono_font_size_offset: i64,
    pub neovide_mono_font_size_offset: i64,
    pub qt_mono_font_size_offset: i64,
    pub vscode_mono_font_size_offset: i64,
    pub zed_mono_font_size_offset: i64,
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
            &repo_root.join("styling/colors"),
        )
        .map(|colors| colors.is_dark())
        .unwrap_or(DEFAULT_DARK_HINT);
        Self {
            color_scheme: DEFAULT_COLOR_SCHEME.to_owned(),
            wallpaper: repo_root
                .join(DEFAULT_WALLPAPER_RELATIVE_PATH)
                .display()
                .to_string(),
            wallpaper_dir: repo_root
                .join(DEFAULT_WALLPAPER_DIR_RELATIVE_PATH)
                .display()
                .to_string(),
            filter_wallpaper: DEFAULT_FILTER_WALLPAPER,
            system_font: DEFAULT_SYSTEM_FONT.to_owned(),
            mono_font: DEFAULT_MONO_FONT.to_owned(),
            icon_theme: DEFAULT_ICON_THEME.to_owned(),
            cursor_theme: DEFAULT_CURSOR_THEME.to_owned(),
            cursor_size: DEFAULT_CURSOR_SIZE,
            font_size: DEFAULT_FONT_SIZE,
            quickshell_font_size_offset: DEFAULT_QUICKSHELL_FONT_SIZE_OFFSET,
            gtk_font_size_offset: DEFAULT_GTK_FONT_SIZE_OFFSET,
            qt_font_size_offset: DEFAULT_QT_FONT_SIZE_OFFSET,
            mono_font_size: DEFAULT_MONO_FONT_SIZE,
            alacritty_mono_font_size_offset: DEFAULT_ALACRITTY_MONO_FONT_SIZE_OFFSET,
            ghostty_mono_font_size_offset: DEFAULT_GHOSTTY_MONO_FONT_SIZE_OFFSET,
            gtk_mono_font_size_offset: DEFAULT_GTK_MONO_FONT_SIZE_OFFSET,
            neovide_mono_font_size_offset: DEFAULT_NEOVIDE_MONO_FONT_SIZE_OFFSET,
            qt_mono_font_size_offset: DEFAULT_QT_MONO_FONT_SIZE_OFFSET,
            vscode_mono_font_size_offset: DEFAULT_VSCODE_MONO_FONT_SIZE_OFFSET,
            zed_mono_font_size_offset: DEFAULT_ZED_MONO_FONT_SIZE_OFFSET,
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

    pub fn font_size_offset_for(&self, target_name: &str) -> crate::Result<i64> {
        let offset = match target_name {
            "quickshell" => self.quickshell_font_size_offset,
            "gtk" => self.gtk_font_size_offset,
            "qt" => self.qt_font_size_offset,
            _ => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("Unknown font size target: {target_name}"),
                )
                .into());
            }
        };
        Ok(offset)
    }

    pub fn font_size_for(&self, target_name: &str) -> crate::Result<i64> {
        Ok(self.font_size + self.font_size_offset_for(target_name)?)
    }

    pub fn mono_font_size_offset_for(&self, target_name: &str) -> crate::Result<i64> {
        let offset = match target_name {
            "alacritty" => self.alacritty_mono_font_size_offset,
            "ghostty" => self.ghostty_mono_font_size_offset,
            "gtk" => self.gtk_mono_font_size_offset,
            "neovide" => self.neovide_mono_font_size_offset,
            "qt" => self.qt_mono_font_size_offset,
            "vscode" => self.vscode_mono_font_size_offset,
            "zed" => self.zed_mono_font_size_offset,
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
        // serde_json's preserve_order feature keeps struct declaration order,
        // which matches THEME_STATE_FIELD_ORDER; flattened `extra` keys land
        // after the typed fields. The exact output is pinned by the
        // state_serialization_matches_legacy_output test.
        match serde_json::to_value(self) {
            Ok(Value::Object(map)) => map,
            _ => unreachable!("ThemeState serializes to a JSON object"),
        }
    }
}

#[cfg(test)]
mod dim_ramp_tests {
    use super::{ColorScheme, dim_ramp};
    use std::{fs, path::PathBuf};

    fn relative_luminance(hex: &str) -> f64 {
        let digits = hex.trim_start_matches('#');
        let channel = |start: usize| {
            let value =
                f64::from(u8::from_str_radix(&digits[start..start + 2], 16).unwrap()) / 255.0;
            if value <= 0.03928 {
                value / 12.92
            } else {
                ((value + 0.055) / 1.055).powf(2.4)
            }
        };
        0.2126 * channel(0) + 0.7152 * channel(2) + 0.0722 * channel(4)
    }

    fn contrast(a: &str, b: &str) -> f64 {
        let (a, b) = (relative_luminance(a), relative_luminance(b));
        (a.max(b) + 0.05) / (a.min(b) + 0.05)
    }

    fn every_scheme() -> Vec<(String, ColorScheme)> {
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../styling/colors");
        let mut schemes = Vec::new();
        for entry in fs::read_dir(dir).expect("styling/colors is readable") {
            let path = entry.expect("readable entry").path();
            if path.extension().is_none_or(|ext| ext != "json") {
                continue;
            }
            let name = path.file_stem().unwrap().to_string_lossy().into_owned();
            let text = fs::read_to_string(&path).expect("scheme is readable");
            schemes.push((name, serde_json::from_str(&text).expect("scheme parses")));
        }
        assert!(!schemes.is_empty(), "expected scheme files on disk");
        schemes
    }

    #[test]
    fn every_scheme_dims_monotonically_from_fg() {
        for (name, scheme) in every_scheme() {
            let ramp = [
                &scheme.fg,
                &scheme.fg2,
                &scheme.fg3,
                &scheme.fg4,
                &scheme.fg_faint,
            ];
            for pair in ramp.windows(2) {
                let (brighter, dimmer) = (relative_luminance(pair[0]), relative_luminance(pair[1]));
                let ordered = if scheme.is_dark() {
                    brighter > dimmer
                } else {
                    brighter < dimmer
                };
                assert!(
                    ordered,
                    "{name}: {} then {} breaks the prominence ramp",
                    pair[0], pair[1]
                );
            }
        }
    }

    #[test]
    fn workspace_pill_states_stay_distinguishable_in_every_scheme() {
        // Workspaces.qml paints occupied pills fg2 and empty pills fg_faint.
        // Both ride the derived ramp precisely so this gap cannot collapse the
        // way fg4-against-bg3 did in nord, solarized, and tokyo-night.
        for (name, scheme) in every_scheme() {
            let separation = contrast(&scheme.fg2, &scheme.fg_faint);
            assert!(
                separation >= 2.0,
                "{name}: occupied/empty pill contrast {separation:.2} is too low"
            );
            let visibility = contrast(&scheme.fg_faint, &scheme.bg);
            assert!(
                visibility >= 1.35,
                "{name}: empty pill contrast against the bar {visibility:.2} is too low"
            );
        }
    }

    #[test]
    fn dim_ramp_rejects_malformed_colors() {
        assert!(dim_ramp("#zzzzzz", "#000000").is_err());
        assert!(dim_ramp("#fff", "#000000").is_err());
    }
}
