use super::{Assembly, GeneratedContent, TargetMetadata, chromium};
use crate::theme::{
    expand_user_path,
    schema::{ColorScheme, ThemeState},
};

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "helium",
    Assembly::Command,
    &["system_font", "mono_font", "dark_hint"],
);

const HELIUM_CONFIG_DIR: &str = "~/.config/net.imput.helium";

pub fn generate(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::commands(Vec::new()))
}

pub(crate) fn mark_clean_exit() -> crate::Result<()> {
    chromium::mark_clean_exit(&expand_user_path(HELIUM_CONFIG_DIR)?)
}

pub fn persist(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    chromium::write_active_preferences(&expand_user_path(HELIUM_CONFIG_DIR)?, state)
}
