use super::Target;
use crate::theme::{
    command::run,
    expand_user_path,
    schema::{ColorScheme, ThemeState},
};

const OUTPUT_PATH: &str = "~/.config/tmux/colors.conf";

pub const TARGET: Target = Target::standalone("tmux", &["color_scheme"], OUTPUT_PATH, generate)
    .comment("#")
    .on_apply(on_apply);

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<String> {
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
        colors.bg,
        colors.accent,
        colors.bg1,
        colors.fg,
        colors.bg,
        colors.green,
        colors.bg1,
        colors.accent,
    ))
}

pub fn on_apply(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    let output_path = expand_user_path(OUTPUT_PATH)?;
    run(&[
        "tmux".as_ref(),
        "source-file".as_ref(),
        output_path.as_os_str(),
    ])
}
