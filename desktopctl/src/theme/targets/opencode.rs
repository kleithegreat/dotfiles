use super::Target;
use crate::{
    fs_util::{atomic_write, expand_user_path},
    theme::{
        color::blend,
        schema::{ColorScheme, ThemeState},
    },
};
use serde_json::{Map, Value};
use std::path::Path;

pub const TARGET: Target = Target::concat(
    "opencode",
    &["color_scheme"],
    "~/.config/opencode/tui.json",
    "bases/opencode.json",
    generate,
)
.persist(persist);

const THEME_NAME: &str = "desktopctl";
const THEME_OUTPUT_PATH: &str = "~/.config/opencode/themes/desktopctl.json";
const THEME_SCHEMA_URL: &str = "https://opencode.ai/theme.json";

pub fn generate(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<String> {
    let mut root = Map::new();
    root.insert("theme".to_owned(), Value::String(THEME_NAME.to_owned()));

    Ok(serde_json::to_string_pretty(&root)?)
}

pub fn persist(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    write_theme(&expand_user_path(THEME_OUTPUT_PATH)?, colors)
}

fn write_theme(path: &Path, colors: &ColorScheme) -> crate::Result<()> {
    atomic_write(path, render_theme(colors).as_bytes())
}

fn render_theme(colors: &ColorScheme) -> String {
    let diff_alpha = if colors.is_dark() { 0.18 } else { 0.10 };
    let diff_line_alpha = if colors.is_dark() { 0.24 } else { 0.14 };

    let mut theme = Map::new();
    theme.insert("primary".to_owned(), Value::String(colors.accent.clone()));
    theme.insert("secondary".to_owned(), Value::String(colors.purple.clone()));
    theme.insert("accent".to_owned(), Value::String(colors.blue.clone()));
    theme.insert("error".to_owned(), Value::String(colors.red.clone()));
    theme.insert("warning".to_owned(), Value::String(colors.yellow.clone()));
    theme.insert("success".to_owned(), Value::String(colors.green.clone()));
    theme.insert("info".to_owned(), Value::String(colors.cyan.clone()));
    theme.insert("text".to_owned(), Value::String(colors.fg.clone()));
    theme.insert("textMuted".to_owned(), Value::String(colors.fg3.clone()));
    theme.insert("background".to_owned(), Value::String(colors.bg.clone()));
    theme.insert(
        "backgroundPanel".to_owned(),
        Value::String(colors.bg1.clone()),
    );
    theme.insert(
        "backgroundElement".to_owned(),
        Value::String(colors.bg2.clone()),
    );
    theme.insert("border".to_owned(), Value::String(colors.bg3.clone()));
    theme.insert(
        "borderActive".to_owned(),
        Value::String(colors.accent.clone()),
    );
    theme.insert("borderSubtle".to_owned(), Value::String(colors.bg2.clone()));
    theme.insert("diffAdded".to_owned(), Value::String(colors.green.clone()));
    theme.insert("diffRemoved".to_owned(), Value::String(colors.red.clone()));
    theme.insert("diffContext".to_owned(), Value::String(colors.fg4.clone()));
    theme.insert(
        "diffHunkHeader".to_owned(),
        Value::String(colors.blue.clone()),
    );
    theme.insert(
        "diffHighlightAdded".to_owned(),
        Value::String(colors.green_bright.clone()),
    );
    theme.insert(
        "diffHighlightRemoved".to_owned(),
        Value::String(colors.red_bright.clone()),
    );
    theme.insert(
        "diffAddedBg".to_owned(),
        Value::String(blend(&colors.bg, &colors.green, diff_alpha)),
    );
    theme.insert(
        "diffRemovedBg".to_owned(),
        Value::String(blend(&colors.bg, &colors.red, diff_alpha)),
    );
    theme.insert(
        "diffContextBg".to_owned(),
        Value::String(colors.bg1.clone()),
    );
    theme.insert(
        "diffLineNumber".to_owned(),
        Value::String(colors.fg4.clone()),
    );
    theme.insert(
        "diffAddedLineNumberBg".to_owned(),
        Value::String(blend(&colors.bg1, &colors.green, diff_line_alpha)),
    );
    theme.insert(
        "diffRemovedLineNumberBg".to_owned(),
        Value::String(blend(&colors.bg1, &colors.red, diff_line_alpha)),
    );
    theme.insert("markdownText".to_owned(), Value::String(colors.fg.clone()));
    theme.insert(
        "markdownHeading".to_owned(),
        Value::String(colors.accent.clone()),
    );
    theme.insert(
        "markdownLink".to_owned(),
        Value::String(colors.blue.clone()),
    );
    theme.insert(
        "markdownLinkText".to_owned(),
        Value::String(colors.cyan.clone()),
    );
    theme.insert(
        "markdownCode".to_owned(),
        Value::String(colors.green.clone()),
    );
    theme.insert(
        "markdownBlockQuote".to_owned(),
        Value::String(colors.yellow.clone()),
    );
    theme.insert(
        "markdownEmph".to_owned(),
        Value::String(colors.orange.clone()),
    );
    theme.insert(
        "markdownStrong".to_owned(),
        Value::String(colors.fg.clone()),
    );
    theme.insert(
        "markdownHorizontalRule".to_owned(),
        Value::String(colors.bg3.clone()),
    );
    theme.insert(
        "markdownListItem".to_owned(),
        Value::String(colors.blue.clone()),
    );
    theme.insert(
        "markdownListEnumeration".to_owned(),
        Value::String(colors.cyan.clone()),
    );
    theme.insert(
        "markdownImage".to_owned(),
        Value::String(colors.blue.clone()),
    );
    theme.insert(
        "markdownImageText".to_owned(),
        Value::String(colors.cyan.clone()),
    );
    theme.insert(
        "markdownCodeBlock".to_owned(),
        Value::String(colors.fg.clone()),
    );
    theme.insert(
        "syntaxComment".to_owned(),
        Value::String(colors.fg4.clone()),
    );
    theme.insert(
        "syntaxKeyword".to_owned(),
        Value::String(colors.purple.clone()),
    );
    theme.insert(
        "syntaxFunction".to_owned(),
        Value::String(colors.blue.clone()),
    );
    theme.insert(
        "syntaxVariable".to_owned(),
        Value::String(colors.fg.clone()),
    );
    theme.insert(
        "syntaxString".to_owned(),
        Value::String(colors.green.clone()),
    );
    theme.insert(
        "syntaxNumber".to_owned(),
        Value::String(colors.orange.clone()),
    );
    theme.insert("syntaxType".to_owned(), Value::String(colors.cyan.clone()));
    theme.insert(
        "syntaxOperator".to_owned(),
        Value::String(colors.accent.clone()),
    );
    theme.insert(
        "syntaxPunctuation".to_owned(),
        Value::String(colors.fg2.clone()),
    );

    let mut root = Map::new();
    root.insert(
        "$schema".to_owned(),
        Value::String(THEME_SCHEMA_URL.to_owned()),
    );
    root.insert("theme".to_owned(), Value::Object(theme));

    format!(
        "{}\n",
        serde_json::to_string_pretty(&root).unwrap_or_default()
    )
}
