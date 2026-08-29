use super::{Assembly, GeneratedContent, TargetMetadata, scheme_pair};
use crate::{
    paths,
    theme::{
        atomic_write, find_command, json, resolve,
        schema::{ColorScheme, ColorSchemeAppearance, ThemeState},
    },
};
use serde_json::{Map, Value};
use std::{
    borrow::Cow,
    fmt::Write as _,
    path::PathBuf,
    process::{Command, Stdio},
};

pub const METADATA: TargetMetadata = TargetMetadata::new(
    "vicinae",
    Assembly::Import,
    &["color_scheme", "system_font", "icon_theme"],
)
.output("~/.config/vicinae/settings.theme.json")
.managed_paths(&["~/.local/share/vicinae/themes/*.toml"]);

const THEME_OUTPUT_DIR: &str = "vicinae/themes";

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    let mut font = Map::new();
    let mut normal = Map::new();
    normal.insert(
        "family".to_owned(),
        Value::String(state.system_font.clone()),
    );
    font.insert("normal".to_owned(), Value::Object(normal));

    // Both slots name the selected scheme, never the `dark_hint` variant; see
    // the vicinae quirk in docs/theming.md before "fixing" either.
    let mut appearance = Map::new();
    appearance.insert(
        "name".to_owned(),
        Value::String(colors.vicinae_theme_name()),
    );
    appearance.insert(
        "icon_theme".to_owned(),
        Value::String(state.icon_theme.clone()),
    );

    let dark = appearance.clone();
    let light = appearance;

    let mut theme = Map::new();
    theme.insert("dark".to_owned(), Value::Object(dark));
    theme.insert("light".to_owned(), Value::Object(light));

    let mut root = Map::new();
    root.insert("font".to_owned(), Value::Object(font));
    root.insert("theme".to_owned(), Value::Object(theme));

    Ok(GeneratedContent::text(json::format_pretty_value(
        &Value::Object(root),
    )))
}

pub fn persist(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    // The selected scheme's file plus both same-family counterparts. Only the
    // first is named by `generate`; the others are what populate the launcher's
    // own theme picker with the rest of the family, so switching from inside
    // vicinae finds them already rendered.
    let mut candidates = vec![(colors.vicinae_theme_name(), Cow::Borrowed(colors))];

    let light_theme_name = colors.vicinae_light_theme_name();
    if light_theme_name != candidates[0].0 {
        let light_colors = resolve::load_colors(&light_theme_name, &paths::data_path("colors")?)?;
        candidates.push((light_theme_name, Cow::Owned(light_colors)));
    }

    for appearance in [ColorSchemeAppearance::Light, ColorSchemeAppearance::Dark] {
        if let Some(companion) = appearance_companion(colors, appearance)? {
            candidates.push((companion.vicinae_theme_name(), Cow::Owned(companion)));
        }
    }

    let mut written: Vec<String> = Vec::with_capacity(candidates.len());
    for (name, scheme) in candidates {
        if written.contains(&name) {
            continue;
        }
        write_theme_file(&name, &scheme)?;
        written.push(name);
    }

    Ok(())
}

/// Same-family counterpart for `appearance`. `None` when the scheme already has
/// that appearance or no counterpart exists.
fn appearance_companion(
    colors: &ColorScheme,
    appearance: ColorSchemeAppearance,
) -> crate::Result<Option<ColorScheme>> {
    if colors.appearance == appearance {
        return Ok(None);
    }

    let catalog = scheme_pair::load_scheme_catalog()?;
    Ok(
        scheme_pair::scheme_for_appearance(&catalog, colors, appearance)
            .map(|entry| entry.colors.clone()),
    )
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

    // Detached: this replaces the server with a long-lived one, so waiting on
    // it would hang the apply for as long as the launcher runs.
    let _child = Command::new(&vicinae)
        .arg("server")
        .arg("--replace")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;

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
    let variant = if colors.is_light() { "light" } else { "dark" };

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
        test_support::{ScopedEnvVar, TempDir, env_lock, repo_root},
        theme::targets::testsupport::{dummy_colors, dummy_state, load_repo_colors},
    };
    use std::fs;

    fn text(content: crate::Result<GeneratedContent>) -> String {
        match content.expect("target generation succeeds") {
            GeneratedContent::Text(text) => text,
            GeneratedContent::Commands(_) => panic!("expected text content"),
        }
    }

    #[test]
    fn generate_writes_theme_names_and_font() {
        let _lock = env_lock();
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        let mut state = dummy_state();
        state.dark_hint = true;
        let rendered = text(generate(&load_repo_colors("gruvbox-dark"), &state));
        let value: Value = serde_json::from_str(&rendered).expect("valid json");

        assert_eq!(
            value["font"]["normal"]["family"],
            Value::String("Overpass".to_owned())
        );
        assert_eq!(
            value["theme"]["dark"]["name"],
            Value::String("gruvbox-dark".to_owned())
        );
        assert_eq!(
            value["theme"]["dark"]["icon_theme"],
            Value::String("Neuwaita".to_owned())
        );
        assert_eq!(
            value["theme"]["light"]["icon_theme"],
            Value::String("Neuwaita".to_owned())
        );
    }

    /// Vicinae reads the system appearance itself and can disagree with the
    /// `dark_hint` that qt and gtk follow, so neither slot is allowed to name a
    /// theme other than the one the desktop is actually presenting.
    #[test]
    fn generate_pins_both_slots_to_the_selected_scheme() {
        let _lock = env_lock();
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        let mut state = dummy_state();
        state.dark_hint = false;
        let rendered = text(generate(&load_repo_colors("solarized-light"), &state));
        let value: Value = serde_json::from_str(&rendered).expect("valid json");

        assert_eq!(
            value["theme"]["light"]["name"],
            Value::String("solarized-light".to_owned())
        );
        assert_eq!(
            value["theme"]["dark"]["name"],
            Value::String("solarized-light".to_owned())
        );
    }

    /// The launcher shows what was selected. `dark_hint` swaps the system
    /// chrome to a same-family variant; it does not get to overrule an
    /// explicit scheme choice here.
    #[test]
    fn generate_ignores_dark_hint_in_favour_of_the_selected_scheme() {
        let _lock = env_lock();
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        for dark_hint in [false, true] {
            let mut state = dummy_state();
            state.dark_hint = dark_hint;
            let rendered = text(generate(&load_repo_colors("catppuccin-latte"), &state));
            let value: Value = serde_json::from_str(&rendered).expect("valid json");

            for slot in ["dark", "light"] {
                assert_eq!(
                    value["theme"][slot]["name"],
                    Value::String("catppuccin-latte".to_owned()),
                    "{slot} slot with dark_hint={dark_hint}"
                );
            }
        }
    }

    #[test]
    fn render_theme_matches_expected_shape() {
        let rendered = render_theme("gruvbox-dark", &dummy_colors());

        assert!(rendered.is_ascii(), "{rendered}");
        assert!(rendered.contains("name = \"Gruvbox Dark\""));
        assert!(
            rendered.contains("description = \"Generated from desktopctl theme gruvbox-dark\"")
        );
        assert!(rendered.contains("variant = \"dark\""));
        assert!(rendered.contains("inherits = \"vicinae-dark\""));
        assert!(rendered.contains("[colors.core]\nbackground = \"#000000\"\nforeground = \"#f0f0f0\"\nsecondary_background = \"#020202\"\nborder = \"#040404\"\naccent = \"#3366ff\""));
        assert!(rendered.contains("[colors.list.item.selection]\nbackground = \"#030303\"\nsecondary_background = \"#020202\""));
        assert!(rendered.contains("[colors.grid.item]\nbackground = \"#020202\""));
    }

    #[test]
    fn persist_writes_current_and_light_companion_theme_files() {
        let _lock = env_lock();
        let data_home = TempDir::new("desktopctl-vicinae-data").expect("temp dir");
        let _data = ScopedEnvVar::set("XDG_DATA_HOME", data_home.path().as_os_str());
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());
        let colors = load_repo_colors("solarized-dark");

        persist(&colors, &dummy_state()).expect("persist succeeds");

        let dark = fs::read_to_string(data_home.path().join("vicinae/themes/solarized-dark.toml"))
            .expect("dark theme written");
        let light =
            fs::read_to_string(data_home.path().join("vicinae/themes/solarized-light.toml"))
                .expect("light theme written");

        assert!(dark.contains("variant = \"dark\""));
        assert!(dark.contains("background = \"#002b36\""));
        assert!(light.contains("variant = \"light\""));
        assert!(light.contains("background = \"#fdf6e3\""));
    }

    /// The file `generate` names has to exist, whichever way the hint points.
    #[test]
    fn persist_covers_the_theme_generate_names() {
        for dark_hint in [false, true] {
            let _lock = env_lock();
            let data_home = TempDir::new("desktopctl-vicinae-hint").expect("temp dir");
            let _data = ScopedEnvVar::set("XDG_DATA_HOME", data_home.path().as_os_str());
            let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

            let colors = load_repo_colors("solarized-light");
            let mut state = dummy_state();
            state.dark_hint = dark_hint;

            persist(&colors, &state).expect("persist succeeds");

            let rendered = text(generate(&colors, &state));
            let value: Value = serde_json::from_str(&rendered).expect("valid json");
            let named = value["theme"]["dark"]["name"]
                .as_str()
                .expect("dark slot names a theme");

            assert!(
                data_home
                    .path()
                    .join(format!("vicinae/themes/{named}.toml"))
                    .is_file(),
                "dark_hint={dark_hint} names {named} but no such theme file was written"
            );
        }
    }

    #[test]
    fn persist_writes_dark_companion_theme_for_light_schemes() {
        let _lock = env_lock();
        let data_home = TempDir::new("desktopctl-vicinae-dark-data").expect("temp dir");
        let _data = ScopedEnvVar::set("XDG_DATA_HOME", data_home.path().as_os_str());
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());
        let colors = load_repo_colors("catppuccin-latte");

        persist(&colors, &dummy_state()).expect("persist succeeds");

        let dark = fs::read_to_string(
            data_home
                .path()
                .join("vicinae/themes/catppuccin-mocha.toml"),
        )
        .expect("dark companion written");
        assert!(dark.contains("variant = \"dark\""));
        assert!(dark.contains("background = \"#1e1e2e\""));
    }
}
