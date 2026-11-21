use super::Target;
use crate::theme::schema::{ColorScheme, ThemeState};

pub const TARGET: Target = Target::standalone(
    "neovide",
    &[
        "mono_font",
        "mono_font_size",
        "neovide_mono_font_size_offset",
    ],
    "~/.config/nvim/lua/neovide-theme.lua",
    generate,
)
.comment("--");

pub fn generate(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<String> {
    let guifont = crate::hypr::lua_str(&format!(
        "{}:h{}",
        state.mono_font,
        state.mono_font_size_for(TARGET.name)?,
    ));
    Ok(format!("vim.o.guifont = {guifont}\n"))
}
