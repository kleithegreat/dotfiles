use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "neovide",
    Assembly::Standalone,
    &[
        "mono_font",
        "mono_font_size",
        "neovide_mono_font_size_offset",
    ],
)
.output("~/.config/nvim/lua/neovide-theme.lua")
.comment("--");

pub fn generate(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
        "vim.o.guifont = \"{}:h{}\"\n",
        state.mono_font,
        state.mono_font_size_for(METADATA.name)?,
    )))
}
