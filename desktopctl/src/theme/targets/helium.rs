use super::{Target, chromium};
use crate::theme::{
    expand_user_path,
    schema::{ColorScheme, ThemeState},
};

pub const TARGET: Target = Target::hooks("helium", &["system_font", "mono_font"]).persist(persist);

const HELIUM_CONFIG_DIR: &str = "~/.config/net.imput.helium";

pub(crate) fn mark_clean_exit() -> crate::Result<()> {
    chromium::mark_clean_exit(&expand_user_path(HELIUM_CONFIG_DIR)?)
}

pub fn persist(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    chromium::write_active_preferences(&expand_user_path(HELIUM_CONFIG_DIR)?, state)
}
