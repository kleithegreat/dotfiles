use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    expand_user_path, json,
    schema::{ColorScheme, ThemeState},
};
use rusqlite::{Connection, params};
use serde_json::{Map, Value};

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "vscode",
    assembly: Assembly::Concat,
    output_path: Some("~/.config/Code/User/settings.json"),
    base_path: Some("~/repos/dotfiles/config/vscode/base.json"),
    extra_outputs: &[],
    reload_cmd: None,
    comment: None,
    sync_safe: true,
};

const STATE_DB: &str = "~/.config/Code/User/globalStorage/state.vscdb";

fn resolve_theme(family: &str, variant: &str) -> String {
    match (family, variant) {
        ("gruvbox", "dark") => "Gruvbox Dark Medium".to_owned(),
        ("gruvbox", "light") => "Gruvbox Light Medium".to_owned(),
        ("catppuccin", "mocha") => "Catppuccin Mocha".to_owned(),
        ("catppuccin", "latte") => "Catppuccin Latte".to_owned(),
        ("catppuccin", "frappe") => "Catppuccin Frapp\u{00e9}".to_owned(),
        ("catppuccin", "macchiato") => "Catppuccin Macchiato".to_owned(),
        ("solarized", "dark") => "Solarized Dark+".to_owned(),
        ("solarized", "light") => "Solarized Light+".to_owned(),
        ("rose-pine", "dark") => "Ros\u{00e9} Pine".to_owned(),
        ("rose-pine", "light") => "Ros\u{00e9} Pine Dawn".to_owned(),
        _ => format!("{family}-{variant}"),
    }
}

fn extension_id(family: &str) -> Option<&'static str> {
    match family {
        "catppuccin" => Some("catppuccin.catppuccin-vsc"),
        "gruvbox" => Some("jdinhlife.gruvbox"),
        "rose-pine" => Some("mvllow.rose-pine"),
        _ => None,
    }
}

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let font_size = state.mono_font_size_for(METADATA.name)?;

    let mut root = Map::new();
    root.insert(
        "workbench.colorTheme".to_owned(),
        Value::String(resolve_theme(&colors.family, &colors.variant)),
    );
    root.insert(
        "editor.fontFamily".to_owned(),
        Value::String(state.mono_font.clone()),
    );
    root.insert("editor.fontSize".to_owned(), Value::from(font_size));
    root.insert(
        "terminal.integrated.fontFamily".to_owned(),
        Value::String(state.mono_font.clone()),
    );
    root.insert(
        "terminal.integrated.fontSize".to_owned(),
        Value::from(font_size),
    );

    Ok(GeneratedContent::text(json::format_pretty_value(
        &Value::Object(root),
    )))
}

pub fn persist(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    let Some(extension_id) = extension_id(&colors.family) else {
        return Ok(());
    };

    let db_path = expand_user_path(STATE_DB)?;
    if !db_path.is_file() {
        return Ok(());
    }

    let connection = Connection::open(db_path)?;
    let row = connection.query_row(
        "SELECT value FROM ItemTable WHERE key = ?",
        params!["extensionsIdentifiers/disabled"],
        |row| row.get::<_, String>(0),
    );

    let disabled = match row {
        Ok(value) => value,
        Err(rusqlite::Error::QueryReturnedNoRows) => return Ok(()),
        Err(error) => return Err(error.into()),
    };

    let disabled_value: Value = serde_json::from_str(&disabled)?;
    let Value::Array(entries) = disabled_value else {
        return Ok(());
    };

    let updated = entries
        .into_iter()
        .filter(|entry| {
            entry
                .get("id")
                .and_then(Value::as_str)
                .map(|id| id != extension_id)
                .unwrap_or(true)
        })
        .collect::<Vec<_>>();

    if updated.len() == serde_json::from_str::<Vec<Value>>(&disabled)?.len() {
        return Ok(());
    }

    connection.execute(
        "UPDATE ItemTable SET value = ? WHERE key = ?",
        params![
            json::to_python_string(&updated)?,
            "extensionsIdentifiers/disabled"
        ],
    )?;
    eprintln!("  vscode: enabled extension {extension_id}");
    Ok(())
}
