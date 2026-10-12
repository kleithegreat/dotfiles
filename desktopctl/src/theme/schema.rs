use crate::{
    paths,
    theme::color::{blend, parse_hex},
};
use serde::{Deserialize, Deserializer, Serialize, de};
use serde_json::{Map, Value};
use std::{borrow::Cow, fs, io, path::Path};

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

/// The only source of defaults; there is no compiled fallback.
pub const STATE_SEED_RELATIVE_PATH: &str = "state.json";

/// Keys the seed omits because the wallpaper library is gitignored.
pub const MACHINE_LOCAL_FIELDS: [&str; 2] = ["wallpaper", "wallpaper_dir"];

pub const DEFAULT_WALLPAPER_RELATIVE_PATH: &str = "styling/wallpapers/lmao.png";
/// Picker browse directory, kept apart from `wallpaper` so browsing does not select.
pub const DEFAULT_WALLPAPER_DIR_RELATIVE_PATH: &str = "styling/wallpapers";

/// Known fields in declaration order minus machine-local ones; `extra` keys are dropped.
pub fn seed_json_map(state: &Map<String, Value>) -> Map<String, Value> {
    THEME_STATE_FIELD_ORDER
        .iter()
        .filter(|name| !MACHINE_LOCAL_FIELDS.contains(name))
        .filter_map(|name| {
            state
                .get(*name)
                .map(|value| ((*name).to_owned(), value.clone()))
        })
        .collect()
}

pub fn canonicalize_theme_string_value<'a>(key: &str, value: &'a str) -> Cow<'a, str> {
    match (key, value) {
        ("mono_font", "JetBrains Mono Nerd Font") => Cow::Borrowed("JetBrainsMono Nerd Font"),
        ("mono_font", "Fira Code Nerd Font") => Cow::Borrowed("FiraCode Nerd Font"),
        ("mono_font", "Commit Mono") => Cow::Borrowed("CommitMono"),
        _ => Cow::Borrowed(value),
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ColorSchemeAppearance {
    #[default]
    Light,
    Dark,
}

/// Every scheme file must name its theme in each app; only `ktexteditor` and
/// `vscode.icon_theme` have a fallback.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct ColorSchemeAppThemes {
    pub bat: String,
    #[serde(default)]
    pub ktexteditor: Option<String>,
    pub snappy_switcher: String,
    pub vicinae: VicinaeThemeNames,
    pub vscode: VscodeThemeNames,
    pub zed: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct VicinaeThemeNames {
    pub name: String,
    pub light_name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct VscodeThemeNames {
    pub name: String,
    #[serde(default)]
    pub extension_id: Option<String>,
    /// The icon theme's own id (`catppuccin-mocha`), not the extension id.
    #[serde(default)]
    pub icon_theme: Option<String>,
}

/// Blend fractions from `fg` toward `bg`; strictly increasing, so prominence falls monotonically.
const DIM_RAMP_STEPS: [f64; 4] = [0.15, 0.30, 0.42, 0.70];

pub struct DimRamp {
    pub fg2: String,
    pub fg3: String,
    pub fg4: String,
    pub fg_faint: String,
}

/// Dimmed foreground ramp; see "The fg ramp is derived" in docs/theming.md.
pub fn dim_ramp(fg: &str, bg: &str) -> Result<DimRamp, String> {
    parse_hex(fg)?;
    parse_hex(bg)?;
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
    /// Derived by [`dim_ramp`], never authored.
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

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
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

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
struct ColorSchemeWire {
    family: String,
    variant: String,
    appearance: ColorSchemeAppearance,
    #[serde(default)]
    dark_scheme: Option<String>,
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

    /// Neutral icon set used by every scheme that ships no matching one. It
    /// takes a folder color, so the fallback still tracks the active scheme.
    pub const FALLBACK_VSCODE_ICON_THEME: &'static str = "material-icon-theme";

    pub fn vscode_icon_theme(&self) -> &str {
        self.app_themes
            .vscode
            .icon_theme
            .as_deref()
            .unwrap_or(Self::FALLBACK_VSCODE_ICON_THEME)
    }

    pub fn vscode_extension_id(&self) -> Option<&str> {
        self.app_themes.vscode.extension_id.as_deref()
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
        Self::load_seed(&paths::data_dir()?, &paths::repo_root()?)
    }

    /// A missing, malformed or incomplete seed is fatal by design.
    pub fn load_seed(data_dir: &Path, repo_root: &Path) -> crate::Result<Self> {
        let path = data_dir.join(STATE_SEED_RELATIVE_PATH);
        let text = fs::read_to_string(&path).map_err(|error| {
            io::Error::new(
                error.kind(),
                format!("Cannot read theme state seed {}: {error}", path.display()),
            )
        })?;

        let mut seed: Map<String, Value> = serde_json::from_str(&text).map_err(|error| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("Invalid theme state seed {}: {error}", path.display()),
            )
        })?;

        for (key, relative) in [
            ("wallpaper", DEFAULT_WALLPAPER_RELATIVE_PATH),
            ("wallpaper_dir", DEFAULT_WALLPAPER_DIR_RELATIVE_PATH),
        ] {
            seed.insert(
                key.to_owned(),
                Value::String(repo_root.join(relative).display().to_string()),
            );
        }

        serde_json::from_value(Value::Object(seed)).map_err(|error| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("Invalid theme state seed {}: {error}", path.display()),
            )
            .into()
        })
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
        // preserve_order keeps declaration order (THEME_STATE_FIELD_ORDER); `extra` lands last.
        match serde_json::to_value(self) {
            Ok(Value::Object(map)) => map,
            _ => unreachable!("ThemeState serializes to a JSON object"),
        }
    }
}

#[cfg(test)]
mod dim_ramp_tests {
    use super::{ColorScheme, dim_ramp};
    use crate::theme::color::relative_luminance;
    use std::{fs, path::PathBuf};

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
    fn dim_ramp_rejects_malformed_colors() {
        assert!(dim_ramp("#zzzzzz", "#000000").is_err());
        assert!(dim_ramp("#fff", "#000000").is_err());
    }
}

#[cfg(test)]
mod seed_tests {
    use super::{MACHINE_LOCAL_FIELDS, THEME_STATE_FIELD_ORDER, ThemeState, seed_json_map};
    use crate::test_support::repo_root;
    use serde_json::{Map, Value};
    use std::fs;

    fn seed_object() -> Map<String, Value> {
        let path = repo_root().join("styling/state.json");
        let text = fs::read_to_string(&path).expect("committed state seed exists");
        match serde_json::from_str(&text).expect("committed state seed is JSON") {
            Value::Object(object) => object,
            _ => panic!("committed state seed is not a JSON object"),
        }
    }

    /// Stops a new `ThemeState` field from shipping without a seed value.
    #[test]
    fn seed_covers_exactly_the_non_machine_local_fields() {
        let object = seed_object();
        let expected: Vec<&str> = THEME_STATE_FIELD_ORDER
            .iter()
            .copied()
            .filter(|name| !MACHINE_LOCAL_FIELDS.contains(name))
            .collect();

        let actual: Vec<&str> = object.keys().map(String::as_str).collect();
        assert_eq!(actual, expected);
    }

    #[test]
    fn seed_loads_and_round_trips_through_export() {
        let root = repo_root();
        let state = ThemeState::load_seed(&root.join("styling"), &root).expect("seed loads");
        assert_eq!(seed_json_map(&state.to_ordered_json_map()), seed_object());
    }
}
