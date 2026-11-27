mod alacritty;
mod bat;
mod claude_code;
mod cursor;
mod ghostty;
mod gtk;
mod gtksourceview;
pub(crate) mod helium;
mod hypr_appearance;
mod hyprland;
mod neovide;
mod neovim;
mod opencode;
mod qt;
mod quickshell;
mod sddm;
mod snappy_switcher;
mod starship;
mod t3code;
mod tmux;
mod vicinae;
mod vscode;
mod wallpaper;
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
    sddm::TARGET,
    snappy_switcher::TARGET,
    starship::TARGET,
    t3code::TARGET,
    tmux::TARGET,
    vicinae::TARGET,
    vscode::TARGET,
    wallpaper::TARGET,
    zathura::TARGET,
    zed::TARGET,
    zsh::TARGET,
];

#[cfg(test)]
pub(crate) mod testsupport {
    use crate::test_support::repo_root;
    use crate::theme::schema::{ColorScheme, ThemeState};
    use std::fs;

    /// Every scheme shipped in `styling/colors`, discovered from disk.
    pub fn repo_schemes() -> Vec<String> {
        let mut names = fs::read_dir(repo_root().join("styling/colors"))
            .expect("colors dir")
            .filter_map(|entry| {
                let path = entry.ok()?.path();
                if path.extension()? != "json" {
                    return None;
                }
                Some(path.file_stem()?.to_str()?.to_owned())
            })
            .collect::<Vec<_>>();
        names.sort();
        assert!(!names.is_empty(), "expected scheme files in styling/colors");
        names
    }

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
                "vicinae": "gruvbox-dark",
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
                "comment": "#888888",
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
            }
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
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::schema;

    #[test]
    fn every_target_declares_a_unique_name_in_alphabetical_order() {
        let names = TARGETS.iter().map(|target| target.name).collect::<Vec<_>>();
        assert!(names.windows(2).all(|pair| pair[0] < pair[1]), "{names:?}");
        for target in TARGETS {
            for key in target.state_keys {
                assert!(
                    schema::find_field(key).is_some(),
                    "target '{}' references unknown state key '{key}'",
                    target.name
                );
            }
        }
    }
}
