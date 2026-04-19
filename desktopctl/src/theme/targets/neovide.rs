use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "neovide",
    assembly: Assembly::Standalone,
    output_path: Some("~/.config/nvim/lua/neovide-theme.lua"),
    base_path: None,
    extra_outputs: &[],
    managed_paths: &[],
    reload_cmd: None,
    comment: Some("--"),
    sync_safe: true,
};

pub fn generate(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
        "vim.o.guifont = \"{}:h{}\"\n",
        state.mono_font,
        state.mono_font_size_for(METADATA.name)?,
    )))
}
