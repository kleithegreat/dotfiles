use super::Target;
use crate::{
    cmd::{find_command, spawn_detached},
    fs_util::atomic_write,
    paths,
    theme::{
        color::readable_on_ends,
        schema::{ColorScheme, ThemeState},
    },
};
use std::{
    fmt::Write as _,
    fs,
    path::PathBuf,
    process::{Command, Stdio},
};

pub const TARGET: Target = Target::standalone(
    "vicinae",
    &["color_scheme", "system_font", "icon_theme"],
    "~/.config/vicinae/settings.theme.json",
    generate,
)
.persist(persist)
.on_apply(on_apply);

const THEME_OUTPUT_DIR: &str = "vicinae/themes";

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<String> {
    // Both slots name the selected scheme; see the vicinae quirk in docs/theming.md.
    let appearance = serde_json::json!({
        "name": colors.app_themes.vicinae,
        "icon_theme": state.icon_theme,
    });
    let root = serde_json::json!({
        "font": {
            "normal": {
                "family": state.system_font,
            },
        },
        "theme": {
            "dark": appearance.clone(),
            "light": appearance,
        },
    });

    Ok(format!("{}\n", serde_json::to_string_pretty(&root)?))
}

pub fn persist(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    let active = &colors.app_themes.vicinae;
    write_theme_file(active, colors)?;
    cleanup_managed_themes(active)?;
    Ok(())
}

fn cleanup_managed_themes(keep_name: &str) -> crate::Result<()> {
    let dir = paths::xdg_data_home()?.join(THEME_OUTPUT_DIR);
    let Ok(entries) = fs::read_dir(&dir) else {
        return Ok(());
    };
    let keep_file = format!("{keep_name}.toml");
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("toml") {
            continue;
        }
        if path.file_name().and_then(|n| n.to_str()) == Some(keep_file.as_str()) {
            continue;
        }
        if fs::read_to_string(&path)
            .is_ok_and(|text| text.contains("Generated from desktopctl theme "))
        {
            let _ = fs::remove_file(&path);
        }
    }
    Ok(())
}

/// Restart the launcher so it re-reads the theme just written. Only ever a
/// restart of something already running — `--replace` would otherwise start a
/// server at activation time. See the vicinae quirk in docs/theming.md.
pub fn on_apply(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    let Some(vicinae) = find_command("vicinae") else {
        return Ok(());
    };

    let running = Command::new(&vicinae)
        .arg("ping")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|status| status.success());
    if !running {
        return Ok(());
    }

    // Detached: it replaces the server with a long-lived one.
    spawn_detached([
        vicinae.as_os_str(),
        std::ffi::OsStr::new("server"),
        std::ffi::OsStr::new("--replace"),
    ])?;

    Ok(())
}

fn write_theme_file(theme_name: &str, colors: &ColorScheme) -> crate::Result<()> {
    atomic_write(
        &theme_output_path(theme_name)?,
        render_theme(theme_name, colors).as_bytes(),
    )
}

fn theme_output_path(theme_name: &str) -> crate::Result<PathBuf> {
    Ok(paths::xdg_data_home()?
        .join(THEME_OUTPUT_DIR)
        .join(format!("{theme_name}.toml")))
}

fn render_theme(theme_name: &str, colors: &ColorScheme) -> String {
    let mut rendered = String::new();
    let variant = colors.appearance.as_str();

    writeln!(&mut rendered, "[meta]").expect("string write should succeed");
    writeln!(
        &mut rendered,
        "name = {}",
        toml_string(&display_name(theme_name))
    )
    .expect("string write should succeed");
    writeln!(
        &mut rendered,
        "description = {}",
        toml_string(&format!("Generated from desktopctl theme {theme_name}"))
    )
    .expect("string write should succeed");
    writeln!(&mut rendered, "variant = {}", toml_string(variant))
        .expect("string write should succeed");
    writeln!(
        &mut rendered,
        "inherits = {}",
        toml_string(&format!("vicinae-{variant}"))
    )
    .expect("string write should succeed");
    writeln!(&mut rendered).expect("string write should succeed");

    writeln!(&mut rendered, "[colors.core]").expect("string write should succeed");
    write_color(&mut rendered, "background", &colors.bg);
    write_color(&mut rendered, "foreground", &colors.fg);
    write_color(&mut rendered, "secondary_background", &colors.bg1);
    write_color(&mut rendered, "border", &colors.bg3);
    write_color(&mut rendered, "accent", &colors.accent);
    write_color(
        &mut rendered,
        "accent_foreground",
        &readable_on_ends(&colors.accent, &colors.bg, &colors.fg),
    );
    writeln!(&mut rendered).expect("string write should succeed");

    writeln!(&mut rendered, "[colors.accents]").expect("string write should succeed");
    write_color(&mut rendered, "blue", &colors.blue);
    write_color(&mut rendered, "green", &colors.green);
    write_color(&mut rendered, "magenta", &colors.purple);
    write_color(&mut rendered, "orange", &colors.orange);
    write_color(&mut rendered, "purple", &colors.purple);
    write_color(&mut rendered, "red", &colors.red);
    write_color(&mut rendered, "yellow", &colors.yellow);
    write_color(&mut rendered, "cyan", &colors.cyan);
    writeln!(&mut rendered).expect("string write should succeed");

    writeln!(&mut rendered, "[colors.list.item.selection]").expect("string write should succeed");
    write_color(&mut rendered, "background", &colors.bg2);
    write_color(&mut rendered, "secondary_background", &colors.bg1);
    writeln!(&mut rendered).expect("string write should succeed");

    writeln!(&mut rendered, "[colors.grid.item]").expect("string write should succeed");
    write_color(&mut rendered, "background", &colors.bg1);

    rendered
}

fn write_color(rendered: &mut String, key: &str, value: &str) {
    writeln!(rendered, "{key} = {}", toml_string(value)).expect("string write should succeed");
}

fn toml_string(value: &str) -> String {
    format!("\"{}\"", value.replace('\\', "\\\\").replace('"', "\\\""))
}

fn display_name(theme_name: &str) -> String {
    theme_name
        .split('-')
        .filter(|segment| !segment.is_empty())
        .map(title_case_segment)
        .collect::<Vec<_>>()
        .join(" ")
}

fn title_case_segment(segment: &str) -> String {
    let mut chars = segment.chars();
    match chars.next() {
        Some(first) => format!("{}{}", first.to_ascii_uppercase(), chars.as_str()),
        None => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        test_support::{ScopedEnvVar, TempDir, env_lock},
        theme::targets::testsupport::{dummy_state, load_repo_colors},
    };
    use serde_json::Value;
    use std::fs;

    #[test]
    fn persist_writes_active_theme_and_removes_stale_companion_themes() {
        let _lock = env_lock();
        let data_home = TempDir::new("desktopctl-vicinae-data").expect("temp dir");
        let _data = ScopedEnvVar::set("XDG_DATA_HOME", data_home.path().as_os_str());
        let themes_dir = data_home.path().join(THEME_OUTPUT_DIR);
        fs::create_dir_all(&themes_dir).expect("themes dir");
        fs::write(
            themes_dir.join("solarized-light.toml"),
            "description = \"Generated from desktopctl theme solarized-light\"\n",
        )
        .expect("stale managed theme");
        fs::write(themes_dir.join("custom.toml"), "description = \"Custom\"\n")
            .expect("custom theme");

        let colors = load_repo_colors("solarized-dark");
        persist(&colors, &dummy_state()).expect("persist succeeds");

        let active = fs::read_to_string(themes_dir.join("solarized-dark.toml"))
            .expect("active theme written");
        assert!(active.contains("variant = \"dark\""));
        assert!(active.contains("inherits = \"vicinae-dark\""));
        assert!(active.contains("background = \"#002b36\""));
        assert!(active.contains("accent_foreground = "));
        assert!(!themes_dir.join("solarized-light.toml").exists());
        assert!(themes_dir.join("custom.toml").exists());

        let rendered = generate(&colors, &dummy_state()).expect("generate succeeds");
        let value: Value = serde_json::from_str(&rendered).expect("valid json");
        assert_eq!(value["font"]["normal"]["family"], "Overpass");
        assert_eq!(value["theme"]["dark"]["name"], "solarized-dark");
        assert_eq!(value["theme"]["light"]["name"], "solarized-dark");
    }
}
