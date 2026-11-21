use super::Target;
use crate::{
    cmd::run,
    fs_util::expand_user_path,
    theme::{
        color::readable_on_ends,
        schema::{ColorScheme, ThemeState},
    },
};
use std::ffi::OsStr;

const OUTPUT_PATH: &str = "~/.config/tmux/colors.conf";

pub const TARGET: Target = Target::standalone("tmux", &["color_scheme"], OUTPUT_PATH, generate)
    .comment("#")
    .on_apply(on_apply);

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<String> {
    let on_accent = readable_on_ends(&colors.accent, &colors.bg, &colors.fg);
    let on_green = readable_on_ends(&colors.green, &colors.bg, &colors.fg);

    Ok(format!(
        concat!(
            "set -g status-style \"bg={},fg={}\"\n",
            "set -g status-left \"#[fg={},bg={},bold] #S #[bg={}] \"\n",
            "set -g status-right \"#[fg={}] %H:%M \"\n",
            "setw -g window-status-format \" #I:#W \"\n",
            "setw -g window-status-current-format \"#[fg={},bg={},bold] #I:#W \"\n",
            "set -g pane-border-style \"fg={}\"\n",
            "set -g pane-active-border-style \"fg={}\"\n",
        ),
        colors.bg1,
        colors.fg,
        on_accent,
        colors.accent,
        colors.bg1,
        colors.fg,
        on_green,
        colors.green,
        colors.bg1,
        colors.accent,
    ))
}

pub fn on_apply(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    let output_path = expand_user_path(OUTPUT_PATH)?;
    run([
        OsStr::new("tmux"),
        OsStr::new("source-file"),
        output_path.as_os_str(),
    ])
}
