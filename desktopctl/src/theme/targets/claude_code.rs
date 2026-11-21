use super::Target;
use crate::theme::{
    color::blend,
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

    let base = colors.appearance.as_str();
    let mut root = Map::new();
    root.insert("name".to_owned(), Value::String("desktopctl".to_owned()));
    root.insert("base".to_owned(), Value::String(base.to_owned()));
    root.insert("overrides".to_owned(), Value::Object(overrides));

    Ok(format!("{}\n", serde_json::to_string_pretty(&root)?))
}
