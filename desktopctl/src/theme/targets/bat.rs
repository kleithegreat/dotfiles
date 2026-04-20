use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "bat",
    assembly: Assembly::Standalone,
    output_path: Some("~/.config/bat/config"),
    base_path: None,
    extra_outputs: &[],
    managed_paths: &[],
    state_keys: &["color_scheme"],
    reload_cmd: None,
    comment: None,
    sync_safe: true,
};

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
        "--theme={}\n",
        colors.bat_theme_name()
    )))
}
