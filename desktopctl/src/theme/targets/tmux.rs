use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    expand_user_path, run_owned_command,
    schema::{ColorScheme, ThemeState},
};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "tmux",
    assembly: Assembly::Import,
    output_path: Some("~/.config/tmux/colors.conf"),
    base_path: None,
    extra_outputs: &[],
    managed_paths: &[],
    reload_cmd: None,
    comment: Some("#"),
    sync_safe: true,
};

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
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
    )))
}

pub fn on_apply(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    let output_path = expand_user_path(METADATA.output_path.expect("tmux output path"))?;
    let command = vec![
        "tmux".to_owned(),
        "source-file".to_owned(),
        output_path.display().to_string(),
    ];
    run_owned_command(&command)
}
