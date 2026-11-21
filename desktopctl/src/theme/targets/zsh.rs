use super::Target;
use crate::theme::{
    color::contrast_ratio,
    schema::{ColorScheme, ThemeState},
};

pub const TARGET: Target = Target::standalone(
    "zsh",
    &["color_scheme"],
    "~/.config/zsh/theme-colors",
    generate,
)
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

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<String> {
    Ok(format!(
        "ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg={}'\n",
        autosuggest_color(colors)
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::targets::testsupport::{load_repo_colors, repo_schemes};

    #[test]
    fn repo_schemes_choose_expected_hint_color() {
        // The contract is the property, not the slot: the dimmest step that clears the floor.
        for scheme_name in repo_schemes() {
            let colors = load_repo_colors(&scheme_name);
            let selected = autosuggest_color(&colors);
            assert!(
                contrast_ratio(selected, &colors.bg) >= MIN_HINT_CONTRAST,
                "{scheme_name}: hint color did not meet minimum contrast"
            );

            let dimmer_steps = [
                colors.fg_faint.as_str(),
                colors.fg4.as_str(),
                colors.fg3.as_str(),
                colors.fg2.as_str(),
            ];
            for dimmer in dimmer_steps.iter().take_while(|step| **step != selected) {
                assert!(
                    contrast_ratio(dimmer, &colors.bg) < MIN_HINT_CONTRAST,
                    "{scheme_name}: {dimmer} was dim enough and should have won"
                );
            }
        }
    }
}
