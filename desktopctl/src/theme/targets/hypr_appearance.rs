use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::schema::{ColorScheme, ThemeState};

const RELOAD_CMD: &[&str] = &["hyprctl", "reload"];

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "hypr_appearance",
    Assembly::Standalone,
    &[
        "hypr_gaps_in",
        "hypr_gaps_out",
        "hypr_border_size",
        "hypr_rounding",
        "hypr_blur_enabled",
        "hypr_blur_size",
        "hypr_blur_passes",
        "hypr_animations_enabled",
    ],
)
.output("~/.config/hypr/appearance-theme.lua")
.reload_cmd(RELOAD_CMD)
.comment("--");

fn bool_word(value: bool) -> &'static str {
    if value { "true" } else { "false" }
}

pub fn generate(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
        concat!(
            "return {{\n",
            "    gaps_in            = {},\n",
            "    gaps_out           = {},\n",
            "    border_size        = {},\n",
            "    rounding           = {},\n",
            "    blur_enabled       = {},\n",
            "    blur_size          = {},\n",
            "    blur_passes        = {},\n",
            "    animations_enabled = {},\n",
            "}}\n",
        ),
        state.hypr_gaps_in,
        state.hypr_gaps_out,
        state.hypr_border_size,
        state.hypr_rounding,
        bool_word(state.hypr_blur_enabled),
        state.hypr_blur_size,
        state.hypr_blur_passes,
        bool_word(state.hypr_animations_enabled),
    )))
}
