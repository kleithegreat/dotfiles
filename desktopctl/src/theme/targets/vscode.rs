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

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let font_size = state.mono_font_size_for(METADATA.name)?;

    let mut root = Map::new();
    root.insert(
        "workbench.colorTheme".to_owned(),
        Value::String(colors.vscode_theme_name()),
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
    let Some(extension_id) = colors.vscode_extension_id() else {
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
