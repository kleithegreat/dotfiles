use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    expand_user_path, json,
    schema::{ColorScheme, ThemeState},
};
use rusqlite::{Connection, params};
use serde_json::{Map, Value};

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "vscode",
    Assembly::Concat,
    &[
        "color_scheme",
        "mono_font",
        "mono_font_size",
        "vscode_mono_font_size_offset",
    ],
)
.output("~/.config/Code/User/settings.json")
.base("config/vscode/base.json")
.managed_paths(&["~/.config/Code/User/globalStorage/state.vscdb"]);

const STATE_DB: &str = "~/.config/Code/User/globalStorage/state.vscdb";

fn css_font_family(name: &str) -> String {
    format!("'{}'", name.replace('\\', "\\\\").replace('\'', "\\'"))
}

fn terminal_font_family(name: &str) -> String {
    if name.contains("Nerd Font") && !name.contains("Nerd Font Mono") {
        format!(
            "{}, {}, monospace",
            css_font_family(&format!("{name} Mono")),
            css_font_family(name)
        )
    } else {
        format!("{}, monospace", css_font_family(name))
    }
}

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let font_size = state.mono_font_size_for(METADATA.name)?;

    let mut root = Map::new();
    root.insert(
        "workbench.colorTheme".to_owned(),
        Value::String(colors.vscode_theme_name()),
    );
    root.insert(
        "workbench.iconTheme".to_owned(),
        Value::String(colors.vscode_icon_theme().to_owned()),
    );
    if colors.vscode_icon_theme() == ColorScheme::FALLBACK_VSCODE_ICON_THEME {
        root.insert(
            "material-icon-theme.folders.color".to_owned(),
            Value::String(colors.accent.clone()),
        );
    }
    root.insert(
        "editor.fontFamily".to_owned(),
        Value::String(state.mono_font.clone()),
    );
    root.insert("editor.fontSize".to_owned(), Value::from(font_size));
    root.insert(
        "terminal.integrated.fontFamily".to_owned(),
        Value::String(terminal_font_family(&state.mono_font)),
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

    let original_len = entries.len();
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

    if updated.len() == original_len {
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

#[cfg(test)]
mod tests {
    use super::generate;
    use crate::theme::{
        schema::ColorScheme,
        targets::testsupport::{REPO_SCHEMES, dummy_state, load_repo_colors},
    };

    fn settings(scheme_name: &str) -> serde_json::Value {
        let colors = load_repo_colors(scheme_name);
        let crate::theme::targets::GeneratedContent::Text(text) =
            generate(&colors, &dummy_state()).expect("vscode settings generate")
        else {
            panic!("vscode target generates text");
        };
        serde_json::from_str(&text).expect("generated settings are JSON")
    }

    #[test]
    fn every_scheme_sets_an_icon_theme_alongside_its_color_theme() {
        for scheme_name in REPO_SCHEMES {
            let written = settings(scheme_name);
            let icon_theme = written["workbench.iconTheme"]
                .as_str()
                .unwrap_or_else(|| panic!("{scheme_name}: no icon theme written"));
            assert!(
                !icon_theme.is_empty(),
                "{scheme_name}: icon theme must not be blank"
            );
            assert!(written["workbench.colorTheme"].is_string());
        }
    }

    #[test]
    fn the_neutral_icon_set_is_tinted_but_a_matched_one_is_left_alone() {
        // Catppuccin ships its own icons, so nothing should recolor them.
        let matched = settings("catppuccin-mocha");
        assert_eq!(matched["workbench.iconTheme"], "catppuccin-mocha");
        assert!(matched.get("material-icon-theme.folders.color").is_none());

        // Nord has none, so it falls back and picks up the scheme accent.
        let fallback = settings("nord");
        assert_eq!(
            fallback["workbench.iconTheme"],
            ColorScheme::FALLBACK_VSCODE_ICON_THEME
        );
        assert_eq!(
            fallback["material-icon-theme.folders.color"],
            load_repo_colors("nord").accent
        );
    }
}
