use super::{Assembly, GeneratedContent, TargetMetadata, scheme_pair};
use crate::{
    paths,
    theme::{
        atomic_write, json, resolve,
        schema::{ColorScheme, ColorSchemeAppearance, ThemeState},
    },
};
use serde_json::{Map, Value};
use std::{fmt::Write as _, path::PathBuf};

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

    let mut dark = Map::new();
    dark.insert(
        "name".to_owned(),
        Value::String(match dark_companion(colors)? {
            Some(companion) => companion.vicinae_theme_name(),
            None => colors.vicinae_theme_name(),
        }),
    );
    dark.insert(
        "icon_theme".to_owned(),
        Value::String(state.icon_theme.clone()),
    );

    let mut light = Map::new();
    light.insert(
        "name".to_owned(),
        Value::String(colors.vicinae_light_theme_name()),
    );
    light.insert(
        "icon_theme".to_owned(),
        Value::String(state.icon_theme.clone()),
    );

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
    let theme_name = colors.vicinae_theme_name();
    write_theme_file(&theme_name, colors)?;

    let light_theme_name = colors.vicinae_light_theme_name();
    if light_theme_name != theme_name {
        let light_colors =
            resolve::load_colors(&light_theme_name, &paths::repo_path("themes/colors")?)?;
        write_theme_file(&light_theme_name, &light_colors)?;
    }

    if let Some(companion) = dark_companion(colors)? {
        let dark_theme_name = companion.vicinae_theme_name();
        if dark_theme_name != theme_name {
            write_theme_file(&dark_theme_name, &companion)?;
        }
    }

    Ok(())
}

/// Same-family dark companion referenced by the generated dark slot, so the
/// theme file it names always exists. `None` when the scheme is already dark.
fn dark_companion(colors: &ColorScheme) -> crate::Result<Option<ColorScheme>> {
    if colors.is_dark() {
        return Ok(None);
    }

    let catalog = scheme_pair::load_scheme_catalog()?;
    Ok(
        scheme_pair::scheme_for_appearance(&catalog, colors, ColorSchemeAppearance::Dark)
            .map(|entry| entry.colors.clone()),
    )
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
        test_support::{ScopedEnvVar, TempDir, env_lock},
        theme::targets::testsupport::{dummy_colors, dummy_state, load_repo_colors},
    };
    use std::{
        fs,
        path::{Path, PathBuf},
    };

    fn text(content: crate::Result<GeneratedContent>) -> String {
        match content.expect("target generation succeeds") {
            GeneratedContent::Text(text) => text,
            GeneratedContent::Commands(_) => panic!("expected text content"),
        }
    }

    fn repo_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("desktopctl lives under the repo root")
            .to_path_buf()
    }

    #[test]
    fn generate_writes_theme_names_and_font() {
        let rendered = text(generate(&dummy_colors(), &dummy_state()));
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
            value["theme"]["light"]["name"],
            Value::String("gruvbox-light".to_owned())
        );
        assert_eq!(
            value["theme"]["light"]["icon_theme"],
            Value::String("Neuwaita".to_owned())
        );
    }

    #[test]
    fn generate_dark_slot_uses_declared_dark_pairing_for_light_schemes() {
        let _lock = env_lock();
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());

        let rendered = text(generate(
            &load_repo_colors("catppuccin-latte"),
            &dummy_state(),
        ));
        let value: Value = serde_json::from_str(&rendered).expect("valid json");

        assert_eq!(
            value["theme"]["dark"]["name"],
            Value::String("catppuccin-mocha".to_owned())
        );
        assert_eq!(
            value["theme"]["light"]["name"],
            Value::String("catppuccin-latte".to_owned())
        );
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

    #[test]
    fn persist_writes_dark_companion_theme_for_light_schemes() {
        let _lock = env_lock();
        let data_home = TempDir::new("desktopctl-vicinae-dark-data").expect("temp dir");
        let _data = ScopedEnvVar::set("XDG_DATA_HOME", data_home.path().as_os_str());
        let _repo = ScopedEnvVar::set("DESKTOPCTL_REPO", repo_root().as_os_str());
        let colors = load_repo_colors("catppuccin-latte");

        persist(&colors, &dummy_state()).expect("persist succeeds");

        let dark =
            fs::read_to_string(data_home.path().join("vicinae/themes/catppuccin-mocha.toml"))
                .expect("dark companion written");
        assert!(dark.contains("variant = \"dark\""));
        assert!(dark.contains("background = \"#1e1e2e\""));
    }
}
