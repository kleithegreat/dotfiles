use super::Target;
use crate::theme::{
    color::blend,
    json,
    schema::{ColorScheme, ThemeState},
};
use serde_json::{Map, Value};

/// Only takes effect with `"theme": "custom:desktopctl"` in `~/.claude/settings.json`.
pub const TARGET: Target = Target::standalone(
    "claude_code",
    &["color_scheme"],
    "~/.claude/themes/desktopctl.json",
    generate,
);

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<String> {
    let diff = |ink: &str, ratio: f64| blend(&colors.bg, ink, ratio);
    let overrides = [
        ("text", colors.fg.clone()),
        ("inverseText", colors.bg.clone()),
        ("inactive", colors.fg3.clone()),
        ("inactiveShimmer", colors.fg2.clone()),
        ("subtle", colors.fg4.clone()),
        ("promptBorder", colors.fg4.clone()),
        ("promptBorderShimmer", colors.fg3.clone()),
        ("claude", colors.orange.clone()),
        ("claudeShimmer", colors.orange_bright.clone()),
        ("permission", colors.blue.clone()),
        ("permissionShimmer", colors.blue_bright.clone()),
        ("suggestion", colors.blue.clone()),
        ("remember", colors.blue.clone()),
        ("ide", colors.blue.clone()),
        ("planMode", colors.cyan.clone()),
        ("bashBorder", colors.purple.clone()),
        ("merged", colors.purple.clone()),
        ("success", colors.green.clone()),
        ("error", colors.red.clone()),
        ("warning", colors.yellow.clone()),
        ("warningShimmer", colors.yellow_bright.clone()),
        ("diffAdded", diff(&colors.green, 0.25)),
        ("diffRemoved", diff(&colors.red, 0.25)),
        ("diffAddedDimmed", diff(&colors.green, 0.12)),
        ("diffRemovedDimmed", diff(&colors.red, 0.12)),
        ("diffAddedWord", diff(&colors.green, 0.45)),
        ("diffRemovedWord", diff(&colors.red, 0.45)),
        ("userMessageBackground", colors.bg1.clone()),
        ("userMessageBackgroundHover", colors.bg2.clone()),
        ("bashMessageBackgroundColor", colors.bg1.clone()),
        ("memoryBackgroundColor", colors.bg1.clone()),
        ("composerSidebarBackground", colors.bg_dim.clone()),
        ("selectionBg", colors.bg3.clone()),
        ("clawd_background", colors.bg.clone()),
    ]
    .into_iter()
    .map(|(key, value)| (key.to_owned(), Value::String(value)))
    .collect::<Map<_, _>>();

    let base = if colors.is_dark() { "dark" } else { "light" };
    let mut root = Map::new();
    root.insert("name".to_owned(), Value::String("desktopctl".to_owned()));
    root.insert("base".to_owned(), Value::String(base.to_owned()));
    root.insert("overrides".to_owned(), Value::Object(overrides));

    Ok(format!(
        "{}\n",
        json::format_pretty_value(&Value::Object(root))
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::targets::testsupport::{
        REPO_SCHEMES, dummy_state, load_repo_colors, rose_pine_dawn_colors,
    };

    #[test]
    fn base_follows_scheme_appearance() {
        for scheme in REPO_SCHEMES {
            let colors = load_repo_colors(scheme);
            let value: Value =
                serde_json::from_str(&generate(&colors, &dummy_state()).expect("generates"))
                    .expect("valid json");
            let expected = if colors.is_dark() { "dark" } else { "light" };
            assert_eq!(value["base"], expected, "{scheme}");
        }
    }

    #[test]
    fn overrides_are_hex_colours_claude_code_accepts() {
        let rendered = generate(&rose_pine_dawn_colors(), &dummy_state()).expect("generates");
        let value: Value = serde_json::from_str(&rendered).expect("valid json");
        for (key, colour) in value["overrides"].as_object().expect("overrides object") {
            let colour = colour.as_str().expect("string colour");
            assert!(
                colour.len() == 7
                    && colour.starts_with('#')
                    && colour[1..].chars().all(|c| c.is_ascii_hexdigit()),
                "{key}: {colour}"
            );
        }
    }
}
