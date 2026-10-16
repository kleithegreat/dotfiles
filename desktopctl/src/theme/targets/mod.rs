mod alacritty;
mod bat;
mod chromium;
mod claude_code;
mod cursor;
mod ghostty;
mod gtk;
mod gtksourceview;
pub(crate) mod helium;
mod hypr_appearance;
mod hyprland;
mod kvantum;
mod neovide;
mod neovim;
mod opencode;
mod qt;
mod quickshell;
mod scheme_pair;
mod snappy_switcher;
mod spicetify;
mod starship;
mod t3code;
mod tmux;
mod vicinae;
mod vscode;
mod wallpaper;
mod where_is_my_sddm_theme;
mod zathura;
mod zed;
mod zsh;

use crate::theme::schema::{ColorScheme, ThemeState};

pub type GenerateFn = fn(&ColorScheme, &ThemeState) -> crate::Result<String>;
pub type HookFn = fn(&ColorScheme, &ThemeState) -> crate::Result<()>;

#[derive(Debug, Clone, Copy)]
pub enum Assembly {
    /// The generated text is the whole file at `output`.
    Standalone {
        output: &'static str,
        generate: GenerateFn,
    },
    /// The generated text is appended to (or, for JSON, merged into) `base`.
    Concat {
        output: &'static str,
        base: &'static str,
        generate: GenerateFn,
    },
    /// No output file; only `persist` and `on_apply` act.
    Hooks,
}

#[derive(Debug, Clone, Copy)]
pub struct Target {
    pub name: &'static str,
    pub assembly: Assembly,
    pub state_keys: &'static [&'static str],
    pub reload_cmd: Option<&'static [&'static str]>,
    pub comment: Option<&'static str>,
    pub sync_safe: bool,
    pub persist: Option<HookFn>,
    pub on_apply: Option<HookFn>,
}

impl Target {
    const fn new(
        name: &'static str,
        assembly: Assembly,
        state_keys: &'static [&'static str],
    ) -> Self {
        Self {
            name,
            assembly,
            state_keys,
            reload_cmd: None,
            comment: None,
            sync_safe: true,
            persist: None,
            on_apply: None,
        }
    }

    pub const fn standalone(
        name: &'static str,
        state_keys: &'static [&'static str],
        output: &'static str,
        generate: GenerateFn,
    ) -> Self {
        Self::new(name, Assembly::Standalone { output, generate }, state_keys)
    }

    pub const fn concat(
        name: &'static str,
        state_keys: &'static [&'static str],
        output: &'static str,
        base: &'static str,
        generate: GenerateFn,
    ) -> Self {
        Self::new(
            name,
            Assembly::Concat {
                output,
                base,
                generate,
            },
            state_keys,
        )
    }

    pub const fn hooks(name: &'static str, state_keys: &'static [&'static str]) -> Self {
        Self::new(name, Assembly::Hooks, state_keys)
    }

    pub const fn reload_cmd(self, reload_cmd: &'static [&'static str]) -> Self {
        Self {
            reload_cmd: Some(reload_cmd),
            ..self
        }
    }

    pub const fn comment(self, comment: &'static str) -> Self {
        Self {
            comment: Some(comment),
            ..self
        }
    }

    pub const fn sync_safe(self, sync_safe: bool) -> Self {
        Self { sync_safe, ..self }
    }

    pub const fn persist(self, persist: HookFn) -> Self {
        Self {
            persist: Some(persist),
            ..self
        }
    }

    pub const fn on_apply(self, on_apply: HookFn) -> Self {
        Self {
            on_apply: Some(on_apply),
            ..self
        }
    }
}

pub fn get(name: &str) -> Option<&'static Target> {
    TARGETS.iter().find(|target| target.name == name)
}

/// Alphabetical by name.
pub const TARGETS: &[Target] = &[
    alacritty::TARGET,
    bat::TARGET,
    chromium::TARGET,
    claude_code::TARGET,
    cursor::TARGET,
    ghostty::TARGET,
    gtk::TARGET,
    gtksourceview::TARGET,
    helium::TARGET,
    hypr_appearance::TARGET,
    hyprland::TARGET,
    neovide::TARGET,
    neovim::TARGET,
    opencode::TARGET,
    qt::TARGET,
    quickshell::TARGET,
    snappy_switcher::TARGET,
    spicetify::TARGET,
    starship::TARGET,
    t3code::TARGET,
    tmux::TARGET,
    vicinae::TARGET,
    vscode::TARGET,
    wallpaper::TARGET,
    where_is_my_sddm_theme::TARGET,
    zathura::TARGET,
    zed::TARGET,
    zsh::TARGET,
];

#[cfg(test)]
pub(crate) mod testsupport {
    use crate::test_support::repo_root;
    use crate::theme::schema::{ColorScheme, ThemeState};

    /// Every scheme shipped in `styling/colors`, for tests that assert a
    /// property must hold across all of them rather than for a chosen few.
    pub const REPO_SCHEMES: [&str; 14] = [
        "catppuccin-frappe",
        "catppuccin-latte",
        "catppuccin-macchiato",
        "catppuccin-mocha",
        "gruvbox-dark",
        "gruvbox-light",
        "nord",
        "nord-light",
        "rose-pine",
        "rose-pine-dawn",
        "solarized-dark",
        "solarized-light",
        "tokyo-night",
        "tokyo-night-light",
    ];

    pub fn load_repo_colors(scheme_name: &str) -> ColorScheme {
        crate::theme::resolve::load_colors(scheme_name, &repo_root().join("styling/colors"))
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
    use crate::theme::targets::testsupport::{
        dummy_colors, dummy_state, load_repo_colors, rose_pine_dawn_colors,
    };

    fn text(content: crate::Result<String>) -> String {
        content.expect("target generation succeeds")
    }

    #[test]
    fn every_target_declares_a_unique_name_in_alphabetical_order() {
        let names = TARGETS.iter().map(|target| target.name).collect::<Vec<_>>();
        assert!(names.windows(2).all(|pair| pair[0] < pair[1]), "{names:?}");
    }

    #[test]
    fn sync_safety_and_assembly_are_declared_per_target() {
        assert!(matches!(
            get("cursor").expect("cursor target").assembly,
            Assembly::Standalone { .. }
        ));
        assert!(matches!(
            get("chromium").expect("chromium target").assembly,
            Assembly::Hooks
        ));
        assert!(get("gtk").expect("gtk target").sync_safe);
        assert!(
            get("gtksourceview")
                .expect("gtksourceview target")
                .sync_safe
        );
        assert!(!get("wallpaper").expect("wallpaper target").sync_safe);
    }

    #[test]
    fn alacritty_output_is_toml_font_and_palette_sections() {
        let output = text(alacritty::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "[font]\nnormal = { family = \"JetBrains Mono Nerd Font\" }\nsize = 11\n\n[colors.primary]\nbackground = \"#000000\"\nforeground = \"#f0f0f0\"\n\n[colors.normal]\nblack   = \"#000000\"\nred     = \"#111111\"\ngreen   = \"#222222\"\nyellow  = \"#333333\"\nblue    = \"#444444\"\nmagenta = \"#555555\"\ncyan    = \"#666666\"\nwhite   = \"#777777\"\n\n[colors.bright]\nblack   = \"#888888\"\nred     = \"#999999\"\ngreen   = \"#aaaaaa\"\nyellow  = \"#bbbbbb\"\nblue    = \"#cccccc\"\nmagenta = \"#dddddd\"\ncyan    = \"#eeeeee\"\nwhite   = \"#ffffff\"\n"
        );
    }

    #[test]
    fn hyprland_output_is_a_lua_data_table() {
        let output = text(hyprland::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "return {\n    bg_rgba        = \"rgba(000000ff)\",\n    bg1_rgba       = \"rgba(020202ff)\",\n    fg_rgba        = \"rgba(f0f0f0ff)\",\n    red_rgba       = \"rgba(ff0000ff)\",\n    green_rgba     = \"rgba(00ff00ff)\",\n    yellow_rgba    = \"rgba(ffff00ff)\",\n    sys_font       = \"Overpass\",\n}\n"
        );
    }

    #[test]
    fn hypr_appearance_output_is_a_lua_data_table() {
        let output = text(hypr_appearance::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "return {\n    gaps_in            = 4,\n    gaps_out           = 6,\n    border_size        = 2,\n    rounding           = 8,\n    blur_enabled       = true,\n    blur_size          = 8,\n    blur_passes        = 2,\n    animations_enabled = true,\n}\n"
        );
    }

    #[test]
    fn quickshell_output_is_a_colors_and_fonts_document() {
        let output = text(quickshell::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "{\n  \"colors\": {\n    \"bg\": \"#000000\",\n    \"bg1\": \"#020202\",\n    \"fg\": \"#f0f0f0\",\n    \"fg2\": \"#cccccc\",\n    \"fg3\": \"#a8a8a8\",\n    \"fg4\": \"#8b8b8b\",\n    \"redBright\": \"#ff1111\",\n    \"greenBright\": \"#11ff11\",\n    \"yellowBright\": \"#ffff11\",\n    \"accent\": \"#3366ff\"\n  },\n  \"fonts\": {\n    \"family\": \"JetBrains Mono Nerd Font\",\n    \"systemFamily\": \"Overpass\",\n    \"size\": 11\n  }\n}\n"
        );
    }

    #[test]
    fn quickshell_output_applies_font_size_offset() {
        let mut state = dummy_state();
        state.quickshell_font_size_offset = 2;

        let output = text(quickshell::generate(&dummy_colors(), &state));
        assert!(output.contains("\"size\": 13\n"), "{output}");
    }

    #[test]
    fn neovim_output_carries_the_palette_and_tracks_scheme_lightness() {
        let output = text(neovim::generate(&dummy_colors(), &dummy_state()));
        assert!(output.contains("background = \"dark\","), "{output}");
        assert!(output.contains("accent = \"#3366ff\","), "{output}");
        assert!(output.contains("fg_faint = \"#484848\","), "{output}");
        assert!(
            output.contains("terminal = {\n    \"#000000\","),
            "{output}"
        );

        let output = text(neovim::generate(&rose_pine_dawn_colors(), &dummy_state()));
        assert!(output.contains("background = \"light\","), "{output}");
    }

    #[test]
    fn neovide_output_sets_guifont_with_size() {
        let output = text(neovide::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(output, "vim.o.guifont = \"JetBrains Mono Nerd Font:h11\"\n");
    }

    #[test]
    fn bat_output_quotes_the_scheme_theme() {
        let output = text(bat::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(output, "--theme=\"gruvbox-dark\"\n");

        let spaced = text(bat::generate(
            &load_repo_colors("solarized-light"),
            &dummy_state(),
        ));
        assert_eq!(spaced, "--theme=\"Solarized (light)\"\n");
    }

    #[test]
    fn ghostty_output_is_key_values_with_an_indexed_palette() {
        let output = text(ghostty::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "font-family = JetBrains Mono Nerd Font\nfont-size = 11\nbackground = #000000\nforeground = #f0f0f0\nselection-background = #040404\nselection-foreground = #f0f0f0\ncursor-color = #f0f0f0\ncursor-text = #000000\npalette = 0=#000000\npalette = 1=#111111\npalette = 2=#222222\npalette = 3=#333333\npalette = 4=#444444\npalette = 5=#555555\npalette = 6=#666666\npalette = 7=#777777\npalette = 8=#888888\npalette = 9=#999999\npalette = 10=#aaaaaa\npalette = 11=#bbbbbb\npalette = 12=#cccccc\npalette = 13=#dddddd\npalette = 14=#eeeeee\npalette = 15=#ffffff\n"
        );
    }

    #[test]
    fn zsh_output_sets_autosuggest_highlight_style() {
        let output = text(zsh::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(output, "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#8b8b8b'\n");
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
    fn qt_output_is_a_colorscheme_ini_with_three_states() {
        let mut state = dummy_state();
        state.dark_hint = true;
        let output = text(qt::generate(&dummy_colors(), &state));

        let mut lines = output.lines();
        assert_eq!(lines.next(), Some("[ColorScheme]"));
        for (line, key) in lines.zip(["active_colors", "disabled_colors", "inactive_colors"]) {
            let values = line
                .strip_prefix(&format!("{key}="))
                .unwrap_or_else(|| panic!("{key} row"));
            assert_eq!(values.split(", ").count(), 21, "{key} role count");

            // Index 13 is HighlightedText over index 12's Highlight. Pairing it
            // with the scheme's body `fg` drops light schemes to ~1.6:1. The
            // disabled row is exempt: dimmed selected text is the point there.
            if key == "disabled_colors" {
                continue;
            }
            let role =
                |index: usize| format!("#{}", &values.split(", ").nth(index).expect("role")[3..]);
            assert!(
                crate::theme::color::contrast_ratio(&role(12), &role(13)) >= 4.5,
                "{key}: selected text is unreadable on the highlight"
            );
        }
    }

    #[test]
    fn cursor_output_inherits_the_scheme_icon_theme() {
        let output = text(cursor::generate(&dummy_colors(), &dummy_state()));
        assert_eq!(
            output,
            "[Icon Theme]\nName=Default\nInherits=BreezeX-RosePine-Linux\n"
        );
    }

    #[test]
    fn vscode_json_escapes_non_ascii_scheme_names() {
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
}
