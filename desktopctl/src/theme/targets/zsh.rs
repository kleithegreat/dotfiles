use super::{Assembly, GeneratedContent, TargetMetadata, color_utils::contrast_ratio};
use crate::theme::schema::{ColorScheme, ThemeState};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "zsh",
    assembly: Assembly::Import,
    output_path: Some("~/.config/zsh/theme-colors"),
    base_path: None,
    extra_outputs: &[],
    reload_cmd: None,
    comment: Some("#"),
    sync_safe: true,
};

const MIN_HINT_CONTRAST: f64 = 3.0;

fn autosuggest_color(colors: &ColorScheme) -> &str {
    // Light schemes keep hints muted through fg2; on dark schemes fg2 is often
    // brighter than the main foreground, so fall back straight to fg there.
    if colors.is_light() {
        for candidate in [
            colors.fg4.as_str(),
            colors.fg3.as_str(),
            colors.fg2.as_str(),
            colors.fg.as_str(),
        ] {
            if contrast_ratio(candidate, &colors.bg) >= MIN_HINT_CONTRAST {
                return candidate;
            }
        }
    } else {
        for candidate in [colors.fg4.as_str(), colors.fg3.as_str(), colors.fg.as_str()] {
            if contrast_ratio(candidate, &colors.bg) >= MIN_HINT_CONTRAST {
                return candidate;
            }
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
    use crate::theme::targets::testsupport::load_repo_colors;

    fn expected_color<'a>(colors: &'a ColorScheme, field: &str) -> &'a str {
        match field {
            "fg" => colors.fg.as_str(),
            "fg2" => colors.fg2.as_str(),
            "fg3" => colors.fg3.as_str(),
            "fg4" => colors.fg4.as_str(),
            _ => panic!("unknown color field: {field}"),
        }
    }

    #[test]
    fn repo_schemes_choose_expected_hint_color() {
        let cases = [
            ("catppuccin-frappe", "fg4"),
            ("catppuccin-latte", "fg4"),
            ("catppuccin-macchiato", "fg4"),
            ("catppuccin-mocha", "fg4"),
            ("gruvbox-dark", "fg4"),
            ("gruvbox-light", "fg4"),
            ("nord", "fg"),
            ("nord-light", "fg4"),
            ("rose-pine", "fg3"),
            ("rose-pine-dawn", "fg2"),
            ("solarized-dark", "fg3"),
            ("solarized-light", "fg2"),
            ("tokyo-night", "fg3"),
            ("tokyo-night-light", "fg2"),
        ];

        for (scheme_name, field) in cases {
            let colors = load_repo_colors(scheme_name);
            let selected = autosuggest_color(&colors);
            assert_eq!(selected, expected_color(&colors, field), "{scheme_name}");
            assert!(
                contrast_ratio(selected, &colors.bg) >= MIN_HINT_CONTRAST,
                "{scheme_name}: selected {field} did not meet minimum contrast"
            );
        }
    }
}
