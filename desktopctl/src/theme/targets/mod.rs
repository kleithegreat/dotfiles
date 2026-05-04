mod alacritty;
mod bat;
mod chromium;
mod color_utils;
mod cursor;
mod ghostty;
mod gtk;
mod gtksourceview;
mod hypr_appearance;
mod hyprland;
mod neovide;
mod neovim;
mod openchamber;
mod opencode;
mod qt;
mod quickshell;
mod snappy_switcher;
mod spicetify;
mod starship;
mod tmux;
mod vicinae;
mod vscode;
mod wallpaper;
mod where_is_my_sddm_theme;
mod zathura;
mod zed;
mod zsh;

use crate::theme::schema::{ColorScheme, ThemeState};
use std::{collections::BTreeMap, io};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Assembly {
    Import,
    Standalone,
    Command,
    Concat,
}

pub type CommandBatch = Vec<Vec<String>>;
pub type GenerateFn = fn(&ColorScheme, &ThemeState) -> crate::Result<GeneratedContent>;
pub type HookFn = fn(&ColorScheme, &ThemeState) -> crate::Result<()>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GeneratedContent {
    Text(String),
    Commands(CommandBatch),
}

impl GeneratedContent {
    pub fn text(content: impl Into<String>) -> Self {
        Self::Text(content.into())
    }

    pub fn commands(commands: CommandBatch) -> Self {
        Self::Commands(commands)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct TargetMetadata {
    pub name: &'static str,
    pub assembly: Assembly,
    pub output_path: Option<&'static str>,
    pub base_path: Option<&'static str>,
    pub extra_outputs: &'static [&'static str],
    pub managed_paths: &'static [&'static str],
    pub state_keys: &'static [&'static str],
    pub reload_cmd: Option<&'static [&'static str]>,
    pub comment: Option<&'static str>,
    pub sync_safe: bool,
}

impl TargetMetadata {
    pub const fn new(
        name: &'static str,
        assembly: Assembly,
        state_keys: &'static [&'static str],
    ) -> Self {
        Self {
            name,
            assembly,
            output_path: None,
            base_path: None,
            extra_outputs: &[],
            managed_paths: &[],
            state_keys,
            reload_cmd: None,
            comment: None,
            sync_safe: true,
        }
    }

    pub const fn output(self, output_path: &'static str) -> Self {
        Self {
            name: self.name,
            assembly: self.assembly,
            output_path: Some(output_path),
            base_path: self.base_path,
            extra_outputs: self.extra_outputs,
            managed_paths: self.managed_paths,
            state_keys: self.state_keys,
            reload_cmd: self.reload_cmd,
            comment: self.comment,
            sync_safe: self.sync_safe,
        }
    }

    pub const fn base(self, base_path: &'static str) -> Self {
        Self {
            name: self.name,
            assembly: self.assembly,
            output_path: self.output_path,
            base_path: Some(base_path),
            extra_outputs: self.extra_outputs,
            managed_paths: self.managed_paths,
            state_keys: self.state_keys,
            reload_cmd: self.reload_cmd,
            comment: self.comment,
            sync_safe: self.sync_safe,
        }
    }

    pub const fn extra_outputs(self, extra_outputs: &'static [&'static str]) -> Self {
        Self {
            name: self.name,
            assembly: self.assembly,
            output_path: self.output_path,
            base_path: self.base_path,
            extra_outputs,
            managed_paths: self.managed_paths,
            state_keys: self.state_keys,
            reload_cmd: self.reload_cmd,
            comment: self.comment,
            sync_safe: self.sync_safe,
        }
    }

    pub const fn managed_paths(self, managed_paths: &'static [&'static str]) -> Self {
        Self {
            name: self.name,
            assembly: self.assembly,
            output_path: self.output_path,
            base_path: self.base_path,
            extra_outputs: self.extra_outputs,
            managed_paths,
            state_keys: self.state_keys,
            reload_cmd: self.reload_cmd,
            comment: self.comment,
            sync_safe: self.sync_safe,
        }
    }

    pub const fn reload_cmd(self, reload_cmd: &'static [&'static str]) -> Self {
        Self {
            name: self.name,
            assembly: self.assembly,
            output_path: self.output_path,
            base_path: self.base_path,
            extra_outputs: self.extra_outputs,
            managed_paths: self.managed_paths,
            state_keys: self.state_keys,
            reload_cmd: Some(reload_cmd),
            comment: self.comment,
            sync_safe: self.sync_safe,
        }
    }

    pub const fn comment(self, comment: &'static str) -> Self {
        Self {
            name: self.name,
            assembly: self.assembly,
            output_path: self.output_path,
            base_path: self.base_path,
            extra_outputs: self.extra_outputs,
            managed_paths: self.managed_paths,
            state_keys: self.state_keys,
            reload_cmd: self.reload_cmd,
            comment: Some(comment),
            sync_safe: self.sync_safe,
        }
    }

    pub const fn sync_safe(self, sync_safe: bool) -> Self {
        Self {
            name: self.name,
            assembly: self.assembly,
            output_path: self.output_path,
            base_path: self.base_path,
            extra_outputs: self.extra_outputs,
            managed_paths: self.managed_paths,
            state_keys: self.state_keys,
            reload_cmd: self.reload_cmd,
            comment: self.comment,
            sync_safe,
        }
    }
}

pub trait Target: Send + Sync {
    fn metadata(&self) -> &TargetMetadata;
    fn generate(&self, colors: &ColorScheme, state: &ThemeState)
    -> crate::Result<GeneratedContent>;

    fn persist(&self, _colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
        Ok(())
    }

    fn on_apply(&self, _colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
        Ok(())
    }
}

pub struct FunctionTarget {
    metadata: TargetMetadata,
    generate: GenerateFn,
    persist: Option<HookFn>,
    on_apply: Option<HookFn>,
}

impl FunctionTarget {
    pub const fn new(metadata: TargetMetadata, generate: GenerateFn) -> Self {
        Self {
            metadata,
            generate,
            persist: None,
            on_apply: None,
        }
    }

    pub const fn with_hooks(
        metadata: TargetMetadata,
        generate: GenerateFn,
        persist: Option<HookFn>,
        on_apply: Option<HookFn>,
    ) -> Self {
        Self {
            metadata,
            generate,
            persist,
            on_apply,
        }
    }
}

impl Target for FunctionTarget {
    fn metadata(&self) -> &TargetMetadata {
        &self.metadata
    }

    fn generate(
        &self,
        colors: &ColorScheme,
        state: &ThemeState,
    ) -> crate::Result<GeneratedContent> {
        (self.generate)(colors, state)
    }

    fn persist(&self, colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
        if let Some(hook) = self.persist {
            hook(colors, state)?;
        }
        Ok(())
    }

    fn on_apply(&self, colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
        if let Some(hook) = self.on_apply {
            hook(colors, state)?;
        }
        Ok(())
    }
}

#[derive(Default)]
pub struct TargetRegistry {
    targets: BTreeMap<&'static str, Box<dyn Target>>,
}

impl TargetRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register<T>(&mut self, target: T) -> crate::Result<()>
    where
        T: Target + 'static,
    {
        self.register_boxed(Box::new(target))
    }

    pub fn register_boxed(&mut self, target: Box<dyn Target>) -> crate::Result<()> {
        validate_metadata(target.metadata())?;
        let name = target.metadata().name;
        if self.targets.contains_key(name) {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                format!("Duplicate TARGET_NAME '{name}'"),
            )
            .into());
        }
        self.targets.insert(name, target);
        Ok(())
    }

    pub fn register_function(
        &mut self,
        metadata: TargetMetadata,
        generate: GenerateFn,
    ) -> crate::Result<()> {
        self.register(FunctionTarget::new(metadata, generate))
    }

    pub fn register_function_with_hooks(
        &mut self,
        metadata: TargetMetadata,
        generate: GenerateFn,
        persist: Option<HookFn>,
        on_apply: Option<HookFn>,
    ) -> crate::Result<()> {
        self.register(FunctionTarget::with_hooks(
            metadata, generate, persist, on_apply,
        ))
    }

    pub fn get(&self, name: &str) -> Option<&dyn Target> {
        self.targets.get(name).map(|target| target.as_ref())
    }

    pub fn iter(&self) -> impl Iterator<Item = (&'static str, &dyn Target)> {
        self.targets
            .iter()
            .map(|(name, target)| (*name, target.as_ref()))
    }
}

fn validate_metadata(metadata: &TargetMetadata) -> crate::Result<()> {
    match metadata.assembly {
        Assembly::Command => {}
        Assembly::Import | Assembly::Standalone => {
            if metadata.output_path.is_none() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("Target '{}' is missing OUTPUT_PATH", metadata.name),
                )
                .into());
            }
        }
        Assembly::Concat => {
            if metadata.output_path.is_none() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("Target '{}' is missing OUTPUT_PATH", metadata.name),
                )
                .into());
            }
            if metadata.base_path.is_none() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    format!("Target '{}' is missing BASE_PATH", metadata.name),
                )
                .into());
            }
        }
    }
    Ok(())
}

type TargetRegistration = (
    &'static TargetMetadata,
    GenerateFn,
    Option<HookFn>,
    Option<HookFn>,
);

macro_rules! target_registration {
    ($module:ident) => {
        (
            &$module::METADATA,
            $module::generate as GenerateFn,
            None,
            None,
        )
    };
    ($module:ident, persist) => {
        (
            &$module::METADATA,
            $module::generate as GenerateFn,
            Some($module::persist as HookFn),
            None,
        )
    };
    ($module:ident, on_apply) => {
        (
            &$module::METADATA,
            $module::generate as GenerateFn,
            None,
            Some($module::on_apply as HookFn),
        )
    };
    ($module:ident, persist, on_apply) => {
        (
            &$module::METADATA,
            $module::generate as GenerateFn,
            Some($module::persist as HookFn),
            Some($module::on_apply as HookFn),
        )
    };
}

const TARGET_REGISTRATIONS: &[TargetRegistration] = &[
    target_registration!(alacritty),
    target_registration!(bat),
    target_registration!(chromium, persist),
    target_registration!(cursor, persist, on_apply),
    target_registration!(ghostty),
    target_registration!(gtk, on_apply),
    target_registration!(gtksourceview, persist, on_apply),
    target_registration!(hypr_appearance),
    target_registration!(hyprland),
    target_registration!(neovide),
    target_registration!(neovim),
    target_registration!(openchamber, persist),
    target_registration!(opencode, persist),
    target_registration!(qt, persist),
    target_registration!(quickshell),
    target_registration!(snappy_switcher, on_apply),
    target_registration!(spicetify, persist, on_apply),
    target_registration!(starship),
    target_registration!(tmux, on_apply),
    target_registration!(vicinae, persist),
    target_registration!(vscode, persist),
    target_registration!(wallpaper, on_apply),
    target_registration!(where_is_my_sddm_theme, persist),
    target_registration!(zathura),
    target_registration!(zed),
    target_registration!(zsh),
];

pub fn build_registry() -> crate::Result<TargetRegistry> {
    let mut registry = TargetRegistry::new();

    for (metadata, generate, persist, on_apply) in TARGET_REGISTRATIONS {
        registry.register_function_with_hooks(**metadata, *generate, *persist, *on_apply)?;
    }

    Ok(registry)
}

#[cfg(test)]
pub(crate) mod testsupport {
    use crate::theme::schema::{ColorScheme, ThemeState};
    use std::path::{Path, PathBuf};

    fn repo_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("desktopctl lives under the repo root")
            .to_path_buf()
    }

    pub fn load_repo_colors(scheme_name: &str) -> ColorScheme {
        crate::theme::resolve::load_colors(scheme_name, &repo_root().join("themes/colors"))
            .expect("repo color scheme should deserialize")
    }

    pub fn dummy_colors() -> ColorScheme {
        serde_json::from_value(serde_json::json!({
            "family": "gruvbox",
            "variant": "dark",
            "appearance": "dark",
            "app_themes": {
                "bat": "gruvbox-dark",
                "ktexteditor": "gruvbox Dark",
                "snappy_switcher": "gruvbox-dark.ini",
                "vicinae": {
                    "name": "gruvbox-dark",
                    "light_name": "gruvbox-light"
                },
                "vscode": {
                    "name": "Gruvbox Dark Medium",
                    "extension_id": "jdinhlife.gruvbox"
                },
                "zed": "Gruvbox Dark"
            },
            "colors": {
                "bg": "#000000",
                "bg_dim": "#010101",
                "bg1": "#020202",
                "bg2": "#030303",
                "bg3": "#040404",
                "fg": "#f0f0f0",
                "fg2": "#e0e0e0",
                "fg3": "#d0d0d0",
                "fg4": "#c0c0c0",
                "red": "#ff0000",
                "green": "#00ff00",
                "yellow": "#ffff00",
                "blue": "#0000ff",
                "purple": "#ff00ff",
                "cyan": "#00ffff",
                "orange": "#ff8800",
                "accent": "#3366ff",
                "red_bright": "#ff1111",
                "green_bright": "#11ff11",
                "yellow_bright": "#ffff11",
                "blue_bright": "#1111ff",
                "purple_bright": "#ff11ff",
                "cyan_bright": "#11ffff",
                "orange_bright": "#ff9911"
            },
            "palette": [
                "#000000", "#111111", "#222222", "#333333",
                "#444444", "#555555", "#666666", "#777777",
                "#888888", "#999999", "#aaaaaa", "#bbbbbb",
                "#cccccc", "#dddddd", "#eeeeee", "#ffffff"
            ]
        }))
        .expect("valid dummy colors")
    }

    pub fn dummy_state() -> ThemeState {
        ThemeState {
            color_scheme: "gruvbox-dark".to_owned(),
            wallpaper: "/tmp/wallpaper.png".to_owned(),
            filter_wallpaper: false,
            system_font: "Overpass".to_owned(),
            mono_font: "JetBrains Mono Nerd Font".to_owned(),
            icon_theme: "Neuwaita".to_owned(),
            cursor_theme: "BreezeX-RosePine-Linux".to_owned(),
            cursor_size: 24,
            font_size: 11,
            quickshell_font_size_offset: 0,
            gtk_font_size_offset: 0,
            qt_font_size_offset: 0,
            chromium_font_size_offset: 0,
            mono_font_size: 11,
            alacritty_mono_font_size_offset: 0,
            ghostty_mono_font_size_offset: 0,
            gtk_mono_font_size_offset: 0,
            neovide_mono_font_size_offset: 0,
            qt_mono_font_size_offset: 0,
            vscode_mono_font_size_offset: 3,
            zed_mono_font_size_offset: 4,
            dark_hint: false,
            hypr_gaps_in: 4,
            hypr_gaps_out: 6,
            hypr_border_size: 2,
            hypr_rounding: 8,
            hypr_blur_enabled: true,
            hypr_blur_size: 8,
            hypr_blur_passes: 2,
            hypr_animations_enabled: true,
            extra: Default::default(),
        }
    }

    pub fn rose_pine_dawn_colors() -> ColorScheme {
        load_repo_colors("rose-pine-dawn")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::schema::ColorSchemeAppearance;
    use crate::theme::targets::testsupport::{
        dummy_colors, dummy_state, load_repo_colors, rose_pine_dawn_colors,
    };

    fn text(content: crate::Result<GeneratedContent>) -> String {
        match content.expect("target generation succeeds") {
            GeneratedContent::Text(value) => value,
            GeneratedContent::Commands(_) => panic!("expected text output"),
        }
    }

    fn commands(content: crate::Result<GeneratedContent>) -> CommandBatch {
        match content.expect("target generation succeeds") {
            GeneratedContent::Commands(value) => value,
            GeneratedContent::Text(_) => panic!("expected command output"),
        }
    }

    #[test]
    fn registry_contains_all_python_targets() {
        let registry = build_registry().expect("registry builds");
        let names = registry.iter().map(|(name, _)| name).collect::<Vec<_>>();
        assert_eq!(names.len(), 26);
        assert!(names.contains(&"chromium"));
        assert!(names.contains(&"cursor"));
        assert!(names.contains(&"gtksourceview"));
        assert!(names.contains(&"openchamber"));
        assert!(names.contains(&"opencode"));
        assert!(names.contains(&"where_is_my_sddm_theme"));
        assert!(names.contains(&"zed"));
        assert!(names.contains(&"zsh"));
        assert_eq!(
            registry
                .get("cursor")
                .expect("cursor target")
                .metadata()
                .assembly,
            Assembly::Standalone
        );
        assert!(
            !registry
                .get("gtk")
                .expect("gtk target")
                .metadata()
                .sync_safe
        );
        assert!(
            registry
                .get("gtksourceview")
                .expect("gtksourceview target")
                .metadata()
                .sync_safe
        );
        assert!(
            !registry
                .get("wallpaper")
                .expect("wallpaper target")
                .metadata()
                .sync_safe
        );

        assert_eq!(
            registry
                .get("chromium")
                .expect("chromium target")
                .metadata()
                .managed_paths,
            &["~/.config/chromium/<profile>/Preferences"]
        );
        assert_eq!(
            registry
                .get("openchamber")
                .expect("openchamber target")
                .metadata()
                .managed_paths,
            &[
                "~/.config/openchamber/settings.json",
                "~/.config/openchamber/themes/desktopctl.json"
            ]
        );
        assert_eq!(
            registry
                .get("opencode")
                .expect("opencode target")
                .metadata()
                .managed_paths,
            &["~/.config/opencode/themes/desktopctl.json"]
        );
        assert_eq!(
            registry
                .get("vscode")
                .expect("vscode target")
                .metadata()
                .managed_paths,
            &["~/.config/Code/User/globalStorage/state.vscdb"]
        );
        assert_eq!(
            registry
                .get("where_is_my_sddm_theme")
                .expect("where_is_my_sddm_theme target")
                .metadata()
                .managed_paths,
            &["/tmp/desktopctl-where-is-my-sddm-theme/background"]
        );
    }

    #[test]
    fn alacritty_output_matches_python_format() {
        let output = text(alacritty::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "[font]\nnormal = { family = \"JetBrains Mono Nerd Font\" }\nsize = 11\n\n[colors.primary]\nbackground = \"#000000\"\nforeground = \"#f0f0f0\"\n\n[colors.normal]\nblack   = \"#000000\"\nred     = \"#111111\"\ngreen   = \"#222222\"\nyellow  = \"#333333\"\nblue    = \"#444444\"\nmagenta = \"#555555\"\ncyan    = \"#666666\"\nwhite   = \"#777777\"\n\n[colors.bright]\nblack   = \"#888888\"\nred     = \"#999999\"\ngreen   = \"#aaaaaa\"\nyellow  = \"#bbbbbb\"\nblue    = \"#cccccc\"\nmagenta = \"#dddddd\"\ncyan    = \"#eeeeee\"\nwhite   = \"#ffffff\"\n"
        );
    }

    #[test]
    fn hyprland_output_matches_python_format() {
        let output = text(hyprland::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "$theme_bg       = rgb(000000)\n$theme_bg_rgba  = rgba(000000ff)\n$theme_bg_dim   = rgb(010101)\n$theme_bg_dim_rgba = rgba(010101ff)\n$theme_bg1      = rgb(020202)\n$theme_bg1_rgba = rgba(020202ff)\n$theme_bg2      = rgb(030303)\n$theme_bg2_rgba = rgba(030303ff)\n$theme_bg3      = rgb(040404)\n$theme_bg3_rgba = rgba(040404ff)\n$theme_fg       = rgb(f0f0f0)\n$theme_fg_rgba  = rgba(f0f0f0ff)\n$theme_accent   = rgb(3366ff)\n$theme_accent_rgba = rgba(3366ffff)\n$theme_red      = rgb(ff0000)\n$theme_red_rgba = rgba(ff0000ff)\n$theme_green    = rgb(00ff00)\n$theme_green_rgba = rgba(00ff00ff)\n$theme_yellow   = rgb(ffff00)\n$theme_yellow_rgba = rgba(ffff00ff)\n$theme_blue     = rgb(0000ff)\n$theme_blue_rgba = rgba(0000ffff)\n$theme_purple   = rgb(ff00ff)\n$theme_purple_rgba = rgba(ff00ffff)\n$theme_cyan     = rgb(00ffff)\n$theme_cyan_rgba = rgba(00ffffff)\n$theme_orange   = rgb(ff8800)\n$theme_orange_rgba = rgba(ff8800ff)\n$theme_font     = JetBrains Mono Nerd Font\n$theme_sys_font = Overpass\n$theme_font_size = 11\n"
        );
    }

    #[test]
    fn hypr_appearance_output_matches_python_format() {
        let output = text(hypr_appearance::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "general {\n    gaps_in = 4\n    gaps_out = 6\n    border_size = 2\n}\n\ndecoration {\n    rounding = 8\n\n    blur {\n        enabled = true\n        size = 8\n        passes = 2\n    }\n}\n\nanimations {\n    enabled = yes\n}\n"
        );
    }

    #[test]
    fn quickshell_output_matches_python_format() {
        let output = text(quickshell::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "{\n  \"colors\": {\n    \"bg\": \"#000000\",\n    \"bg0_h\": \"#010101\",\n    \"bg1\": \"#020202\",\n    \"bg2\": \"#030303\",\n    \"bg3\": \"#040404\",\n    \"fg\": \"#f0f0f0\",\n    \"fg2\": \"#e0e0e0\",\n    \"fg3\": \"#d0d0d0\",\n    \"fg4\": \"#c0c0c0\",\n    \"red\": \"#ff0000\",\n    \"green\": \"#00ff00\",\n    \"yellow\": \"#ffff00\",\n    \"blue\": \"#0000ff\",\n    \"purple\": \"#ff00ff\",\n    \"aqua\": \"#00ffff\",\n    \"orange\": \"#ff8800\",\n    \"redBright\": \"#ff1111\",\n    \"greenBright\": \"#11ff11\",\n    \"yellowBright\": \"#ffff11\",\n    \"blueBright\": \"#1111ff\",\n    \"purpleBright\": \"#ff11ff\",\n    \"aquaBright\": \"#11ffff\",\n    \"orangeBright\": \"#ff9911\",\n    \"accent\": \"#3366ff\"\n  },\n  \"fonts\": {\n    \"family\": \"JetBrains Mono Nerd Font\",\n    \"systemFamily\": \"Overpass\",\n    \"size\": 11,\n    \"sizeSmall\": 9,\n    \"sizeLarge\": 13\n  }\n}\n"
        );
    }

    #[test]
    fn quickshell_output_applies_font_size_offset() {
        let mut state = dummy_state();
        state.quickshell_font_size_offset = 2;

        let output = text(quickshell::generate(&dummy_colors(), &state));
        assert!(
            output.contains("\"size\": 13,\n    \"sizeSmall\": 11,\n    \"sizeLarge\": 15"),
            "{output}"
        );
    }

    #[test]
    fn neovim_output_matches_python_format() {
        let output = text(neovim::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "{\n  \"colorscheme\": \"gruvbox\",\n  \"background\": \"dark\"\n}\n"
        );
    }

    #[test]
    fn neovide_output_matches_python_format() {
        let output = text(neovide::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(output, "vim.o.guifont = \"JetBrains Mono Nerd Font:h11\"\n");
    }

    #[test]
    fn bat_output_matches_python_format() {
        let output = text(bat::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(output, "--theme=gruvbox-dark\n");
    }

    #[test]
    fn ghostty_output_matches_python_format() {
        let output = text(ghostty::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "font-family = JetBrains Mono Nerd Font\nfont-size = 11\nbackground = #000000\nforeground = #f0f0f0\nselection-background = #040404\nselection-foreground = #f0f0f0\ncursor-color = #f0f0f0\ncursor-text = #000000\npalette = 0=#000000\npalette = 1=#111111\npalette = 2=#222222\npalette = 3=#333333\npalette = 4=#444444\npalette = 5=#555555\npalette = 6=#666666\npalette = 7=#777777\npalette = 8=#888888\npalette = 9=#999999\npalette = 10=#aaaaaa\npalette = 11=#bbbbbb\npalette = 12=#cccccc\npalette = 13=#dddddd\npalette = 14=#eeeeee\npalette = 15=#ffffff\n"
        );
    }

    #[test]
    fn zsh_output_sets_autosuggest_highlight_style() {
        let output = text(zsh::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(output, "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#c0c0c0'\n");
    }

    #[test]
    fn opencode_output_sets_managed_theme() {
        let output = text(opencode::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(output, "{\n  \"theme\": \"desktopctl\"\n}");
    }

    #[test]
    fn zed_output_sets_theme_and_fonts() {
        let output = text(zed::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "{\n  \"theme\": \"Gruvbox Dark\",\n  \"buffer_font_family\": \"JetBrains Mono Nerd Font\",\n  \"buffer_font_size\": 15,\n  \"ui_font_family\": \"Overpass\",\n  \"ui_font_size\": 11\n}"
        );
    }

    #[test]
    fn openchamber_generate_returns_no_commands() {
        assert!(commands(openchamber::generate(&dummy_colors(), &dummy_state())).is_empty());
    }

    #[test]
    fn chromium_generate_returns_no_commands() {
        assert!(commands(chromium::generate(&dummy_colors(), &dummy_state())).is_empty());
    }

    #[test]
    fn qt_output_matches_python_format() {
        let output = text(qt::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "[ColorScheme]\nactive_colors=#fff0f0f0, #ff020202, #ff040404, #ff030303, #ff010101, #ff040404, #fff0f0f0, #fff0f0f0, #fff0f0f0, #ff000000, #ff020202, #ff010101, #ff3366ff, #fff0f0f0, #ff0000ff, #ffff00ff, #ff000000, #ff020202, #fff0f0f0, #80c0c0c0, #ff3366ff\ndisabled_colors=#ffc0c0c0, #ff020202, #ff040404, #ff030303, #ff010101, #ff040404, #ffc0c0c0, #fff0f0f0, #ffc0c0c0, #ff000000, #ff020202, #ff010101, #ff3366ff, #ffc0c0c0, #ff0000ff, #ffff00ff, #ff000000, #ff020202, #fff0f0f0, #80c0c0c0, #ff3366ff\ninactive_colors=#fff0f0f0, #ff020202, #ff040404, #ff030303, #ff010101, #ff040404, #fff0f0f0, #fff0f0f0, #fff0f0f0, #ff000000, #ff020202, #ff010101, #ff3366ff, #fff0f0f0, #ff0000ff, #ffff00ff, #ff000000, #ff020202, #fff0f0f0, #80c0c0c0, #ff3366ff\n"
        );
    }

    #[test]
    fn wallpaper_generate_matches_python_behavior() {
        let state = dummy_state();
        assert_eq!(
            commands(wallpaper::generate(&dummy_colors(), &state)),
            vec![vec![
                "awww".to_owned(),
                "img".to_owned(),
                "/tmp/wallpaper.png".to_owned(),
                "--transition-type".to_owned(),
                "fade".to_owned(),
                "--transition-duration".to_owned(),
                "1".to_owned()
            ]]
        );

        let mut filtered_state = state.clone();
        filtered_state.filter_wallpaper = true;
        assert!(commands(wallpaper::generate(&dummy_colors(), &filtered_state)).is_empty());
    }

    #[test]
    fn cursor_generate_matches_python_behavior() {
        let output = text(cursor::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "[Icon Theme]\nName=Default\nInherits=BreezeX-RosePine-Linux\n"
        );
    }

    #[test]
    fn vscode_json_uses_python_ascii_escaping() {
        let output = text(vscode::generate(&rose_pine_dawn_colors(), &dummy_state()));
        assert!(
            output.contains("\"workbench.colorTheme\": \"Ros\\u00e9 Pine Dawn\""),
            "{output}"
        );
    }

    #[test]
    fn vscode_terminal_prefers_mono_nerd_font_variant() {
        let mut state = dummy_state();
        state.mono_font = "JetBrainsMono Nerd Font".to_owned();
        let output = text(vscode::generate(&dummy_colors(), &state));
        assert!(
            output.contains(
                "\"terminal.integrated.fontFamily\": \"'JetBrainsMono Nerd Font Mono', 'JetBrainsMono Nerd Font', monospace\""
            ),
            "{output}"
        );
    }

    #[test]
    fn scheme_metadata_matches_expected_zed_theme_names() {
        let cases = [
            ("catppuccin-frappe", "Catppuccin Frapp\u{00e9}"),
            ("catppuccin-latte", "Catppuccin Latte"),
            ("catppuccin-macchiato", "Catppuccin Macchiato"),
            ("catppuccin-mocha", "Catppuccin Mocha"),
            ("gruvbox-dark", "Gruvbox Dark"),
            ("gruvbox-light", "Gruvbox Light"),
            ("nord", "Nord"),
            ("nord-light", "One Light"),
            ("rose-pine", "Ros\u{00e9} Pine"),
            ("rose-pine-dawn", "Ros\u{00e9} Pine Dawn"),
            ("solarized-dark", "Solarized Dark"),
            ("solarized-light", "Solarized Light"),
            ("tokyo-night", "Tokyo Night"),
            ("tokyo-night-light", "Tokyo Night Light"),
        ];

        for (scheme_name, zed_name) in cases {
            let colors = load_repo_colors(scheme_name);
            assert_eq!(colors.zed_theme_name(), zed_name, "{scheme_name}");
        }
    }

    #[test]
    fn scheme_metadata_matches_expected_app_theme_outputs() {
        let cases = [
            (
                "catppuccin-frappe",
                ColorSchemeAppearance::Dark,
                "Catppuccin Frappe",
                "catppuccin-mocha.ini",
                "catppuccin-frappe",
                "catppuccin-latte",
                "Catppuccin Frapp\u{00e9}",
                Some("catppuccin.catppuccin-vsc"),
            ),
            (
                "catppuccin-latte",
                ColorSchemeAppearance::Light,
                "Catppuccin Latte",
                "catppuccin-latte.ini",
                "catppuccin-latte",
                "catppuccin-latte",
                "Catppuccin Latte",
                Some("catppuccin.catppuccin-vsc"),
            ),
            (
                "catppuccin-macchiato",
                ColorSchemeAppearance::Dark,
                "Catppuccin Macchiato",
                "catppuccin-mocha.ini",
                "catppuccin-macchiato",
                "catppuccin-latte",
                "Catppuccin Macchiato",
                Some("catppuccin.catppuccin-vsc"),
            ),
            (
                "catppuccin-mocha",
                ColorSchemeAppearance::Dark,
                "Catppuccin Mocha",
                "catppuccin-mocha.ini",
                "catppuccin-mocha",
                "catppuccin-latte",
                "Catppuccin Mocha",
                Some("catppuccin.catppuccin-vsc"),
            ),
            (
                "gruvbox-dark",
                ColorSchemeAppearance::Dark,
                "gruvbox-dark",
                "gruvbox-dark.ini",
                "gruvbox-dark",
                "gruvbox-light",
                "Gruvbox Dark Medium",
                Some("jdinhlife.gruvbox"),
            ),
            (
                "gruvbox-light",
                ColorSchemeAppearance::Light,
                "gruvbox-light",
                "catppuccin-latte.ini",
                "gruvbox-light",
                "gruvbox-light",
                "Gruvbox Light Medium",
                Some("jdinhlife.gruvbox"),
            ),
            (
                "nord",
                ColorSchemeAppearance::Dark,
                "base16",
                "nord.ini",
                "nord",
                "nord-light",
                "Nord",
                Some("arcticicestudio.nord-visual-studio-code"),
            ),
            (
                "nord-light",
                ColorSchemeAppearance::Light,
                "base16",
                "catppuccin-latte.ini",
                "nord-light",
                "nord-light",
                "Nord Light",
                Some("huytd.nord-light"),
            ),
            (
                "rose-pine",
                ColorSchemeAppearance::Dark,
                "base16",
                "rose-pine.ini",
                "rose-pine",
                "rose-pine-dawn",
                "Ros\u{00e9} Pine",
                Some("mvllow.rose-pine"),
            ),
            (
                "rose-pine-dawn",
                ColorSchemeAppearance::Light,
                "base16",
                "catppuccin-latte.ini",
                "rose-pine-dawn",
                "rose-pine-dawn",
                "Ros\u{00e9} Pine Dawn",
                Some("mvllow.rose-pine"),
            ),
            (
                "solarized-dark",
                ColorSchemeAppearance::Dark,
                "Solarized (dark)",
                "snappy-slate.ini",
                "solarized-dark",
                "solarized-light",
                "Solarized Dark+",
                Some("ryanolsonx.solarized"),
            ),
            (
                "solarized-light",
                ColorSchemeAppearance::Light,
                "Solarized (light)",
                "catppuccin-latte.ini",
                "solarized-light",
                "solarized-light",
                "Solarized Light+",
                Some("ryanolsonx.solarized"),
            ),
            (
                "tokyo-night",
                ColorSchemeAppearance::Dark,
                "base16",
                "tokyo-night.ini",
                "tokyo-night",
                "tokyo-night-light",
                "Tokyo Night",
                Some("enkia.tokyo-night"),
            ),
            (
                "tokyo-night-light",
                ColorSchemeAppearance::Light,
                "base16",
                "catppuccin-latte.ini",
                "tokyo-night-light",
                "tokyo-night-light",
                "Tokyo Night Light",
                Some("enkia.tokyo-night"),
            ),
        ];

        for (
            scheme_name,
            appearance,
            bat_name,
            snappy_name,
            vicinae_name,
            vicinae_light_name,
            vscode_name,
            vscode_extension_id,
        ) in cases
        {
            let colors = load_repo_colors(scheme_name);
            assert_eq!(colors.appearance, appearance, "{scheme_name}");
            assert_eq!(colors.bat_theme_name(), bat_name, "{scheme_name}");
            assert_eq!(
                colors.snappy_switcher_theme_name(),
                snappy_name,
                "{scheme_name}"
            );
            assert_eq!(colors.vicinae_theme_name(), vicinae_name, "{scheme_name}");
            assert_eq!(
                colors.vicinae_light_theme_name(),
                vicinae_light_name,
                "{scheme_name}"
            );
            assert_eq!(colors.vscode_theme_name(), vscode_name, "{scheme_name}");
            assert_eq!(
                colors.vscode_extension_id(),
                vscode_extension_id,
                "{scheme_name}"
            );
        }
    }
}
