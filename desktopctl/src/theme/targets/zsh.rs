use super::{Assembly, GeneratedContent, TargetMetadata, color_utils::contrast_ratio};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata =
    TargetMetadata::new("zsh", Assembly::Import, &["color_scheme"])
        .output("~/.config/zsh/theme-colors")
        .comment("#");

const MIN_HINT_CONTRAST: f64 = 3.0;

/// The dimmest ramp step that still clears [`MIN_HINT_CONTRAST`]. The ramp
/// dims monotonically on every scheme, so one walk serves light and dark alike.
fn autosuggest_color(colors: &ColorScheme) -> &str {
    for candidate in [
        colors.fg_faint.as_str(),
        colors.fg4.as_str(),
        colors.fg3.as_str(),
        colors.fg2.as_str(),
    ] {
        if contrast_ratio(candidate, &colors.bg) >= MIN_HINT_CONTRAST {
            return candidate;
        }
    }

    colors.fg.as_str()
}

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(format!(
        "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg={}'\n",
        autosuggest_color(colors)
    )))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::targets::testsupport::{REPO_SCHEMES, load_repo_colors};

    #[test]
    fn repo_schemes_choose_expected_hint_color() {
        // Which step wins still varies, because schemes differ in how much
        // contrast exists between fg and bg at all. The contract is the
        // property, not the slot: take the dimmest step that clears the floor.
        for scheme_name in REPO_SCHEMES {
            let colors = load_repo_colors(scheme_name);
            let selected = autosuggest_color(&colors);
            assert!(
                contrast_ratio(selected, &colors.bg) >= MIN_HINT_CONTRAST,
                "{scheme_name}: hint color did not meet minimum contrast"
            );

            let dimmer_steps = [colors.fg_faint.as_str(), colors.fg4.as_str()];
            for dimmer in dimmer_steps.iter().take_while(|step| **step != selected) {
                assert!(
                    contrast_ratio(dimmer, &colors.bg) < MIN_HINT_CONTRAST,
                    "{scheme_name}: {dimmer} was dim enough and should have won"
                );
            }
        }
    }
}
