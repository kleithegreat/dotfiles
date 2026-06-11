use super::{
    Assembly, GeneratedContent, TargetMetadata,
    scheme_pair::{self, SchemeEntry},
};
use crate::theme::{
    atomic_write, expand_user_path,
    schema::{ColorScheme, ColorSchemeAppearance, ThemeState},
};
use std::{collections::HashSet, fs, path::Path, process::Command};

pub const METADATA: TargetMetadata =
    TargetMetadata::new("gtksourceview", Assembly::Standalone, &["color_scheme"])
        .output("~/.local/share/libgedit-gtksourceview-300/styles/desktopctl-current.xml")
        .managed_paths(&["~/.local/share/libgedit-gtksourceview-300/styles/desktopctl-*.xml"]);

const STYLES_DIR: &str = "~/.local/share/libgedit-gtksourceview-300/styles";
const CURRENT_FILE_NAME: &str = "desktopctl-current.xml";
const CURRENT_SCHEME_ID: &str = "desktopctl-current";
const GENERATED_FILE_PREFIX: &str = "desktopctl-";

fn dconf_set(path: &str, value: &str) -> crate::Result<()> {
    let output = Command::new("dconf")
        .args(["write", path, value])
        .output()?;
    if output.status.success() {
        return Ok(());
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    let message = if !stderr.is_empty() {
        stderr
    } else if !stdout.is_empty() {
        stdout
    } else {
        format!("command exited with status {}", output.status)
    };

    Err(std::io::Error::other(message).into())
}

fn style_scheme_id(scheme_name: &str) -> String {
    format!("{GENERATED_FILE_PREFIX}{scheme_name}")
}

fn style_scheme_file_name(scheme_name: &str) -> String {
    format!("{}.xml", style_scheme_id(scheme_name))
}

fn current_style_scheme_name(scheme_name: &str) -> String {
    format!(
        "Desktopctl Current ({})",
        title_case_scheme_name(scheme_name)
    )
}

fn title_case_scheme_name(scheme_name: &str) -> String {
    scheme_name
        .split('-')
        .filter(|part| !part.is_empty())
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                Some(first) => format!("{}{}", first.to_ascii_uppercase(), chars.as_str()),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn render_style_scheme(
    scheme_id: &str,
    display_name: &str,
    scheme_name: &str,
    colors: &ColorScheme,
) -> String {
    let kind = if colors.is_dark() { "dark" } else { "light" };

    format!(
        concat!(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n",
            "<style-scheme id=\"{id}\" _name=\"{name}\" kind=\"{kind}\">\n",
            "  <_description>Generated from desktopctl theme {scheme_name}</_description>\n",
            "\n",
            "  <color name=\"bg\" value=\"{bg}\"/>\n",
            "  <color name=\"bg_dim\" value=\"{bg_dim}\"/>\n",
            "  <color name=\"bg1\" value=\"{bg1}\"/>\n",
            "  <color name=\"bg2\" value=\"{bg2}\"/>\n",
            "  <color name=\"fg\" value=\"{fg}\"/>\n",
            "  <color name=\"fg2\" value=\"{fg2}\"/>\n",
            "  <color name=\"fg3\" value=\"{fg3}\"/>\n",
            "  <color name=\"fg4\" value=\"{fg4}\"/>\n",
            "  <color name=\"red\" value=\"{red}\"/>\n",
            "  <color name=\"green\" value=\"{green}\"/>\n",
            "  <color name=\"yellow\" value=\"{yellow}\"/>\n",
            "  <color name=\"blue\" value=\"{blue}\"/>\n",
            "  <color name=\"blue_bright\" value=\"{blue_bright}\"/>\n",
            "  <color name=\"purple\" value=\"{purple}\"/>\n",
            "  <color name=\"orange\" value=\"{orange}\"/>\n",
            "  <color name=\"cyan\" value=\"{cyan}\"/>\n",
            "  <color name=\"accent\" value=\"{accent}\"/>\n",
            "\n",
            "  <style name=\"text\" foreground=\"fg\" background=\"bg\"/>\n",
            "  <style name=\"selection\" foreground=\"bg\" background=\"accent\"/>\n",
            "  <style name=\"cursor\" foreground=\"fg\"/>\n",
            "  <style name=\"secondary-cursor\" foreground=\"fg4\"/>\n",
            "  <style name=\"current-line\" background=\"bg_dim\"/>\n",
            "  <style name=\"line-numbers\" foreground=\"fg4\" background=\"bg_dim\"/>\n",
            "  <style name=\"right-margin\" foreground=\"bg2\" background=\"bg1\"/>\n",
            "  <style name=\"draw-spaces\" foreground=\"fg4\"/>\n",
            "  <style name=\"bracket-match\" foreground=\"bg\" background=\"fg4\"/>\n",
            "  <style name=\"bracket-mismatch\" foreground=\"bg\" background=\"red\"/>\n",
            "  <style name=\"search-match\" foreground=\"bg\" background=\"yellow\"/>\n",
            "  <style name=\"bookmark\" background=\"bg1\"/>\n",
            "\n",
            "  <style name=\"def:comment\" foreground=\"fg3\" italic=\"true\"/>\n",
            "  <style name=\"def:shebang\" foreground=\"fg3\" bold=\"true\"/>\n",
            "  <style name=\"def:doc-comment\" foreground=\"fg2\" italic=\"true\"/>\n",
            "  <style name=\"def:doc-comment-element\" foreground=\"fg2\" italic=\"true\"/>\n",
            "  <style name=\"def:type\" foreground=\"yellow\"/>\n",
            "  <style name=\"def:constant\" foreground=\"cyan\"/>\n",
            "  <style name=\"def:decimal\" foreground=\"purple\"/>\n",
            "  <style name=\"def:base-n-integer\" foreground=\"purple\"/>\n",
            "  <style name=\"def:floating-point\" foreground=\"purple\"/>\n",
            "  <style name=\"def:character\" foreground=\"green\"/>\n",
            "  <style name=\"def:string\" foreground=\"green\"/>\n",
            "  <style name=\"def:special-char\" foreground=\"orange\"/>\n",
            "  <style name=\"def:builtin\" foreground=\"yellow\"/>\n",
            "  <style name=\"def:identifier\" foreground=\"blue\"/>\n",
            "  <style name=\"def:function\" foreground=\"blue_bright\"/>\n",
            "  <style name=\"def:statement\" foreground=\"red\"/>\n",
            "  <style name=\"def:operator\" foreground=\"orange\"/>\n",
            "  <style name=\"def:preprocessor\" foreground=\"purple\"/>\n",
            "  <style name=\"def:note\" foreground=\"blue_bright\" bold=\"true\"/>\n",
            "  <style name=\"def:warning\" foreground=\"orange\" bold=\"true\"/>\n",
            "  <style name=\"def:error\" foreground=\"red\" bold=\"true\" underline=\"single\"/>\n",
            "  <style name=\"def:underlined\" underline=\"single\"/>\n",
            "</style-scheme>\n",
        ),
        id = scheme_id,
        name = display_name,
        kind = kind,
        scheme_name = scheme_name,
        bg = colors.bg,
        bg_dim = colors.bg_dim,
        bg1 = colors.bg1,
        bg2 = colors.bg2,
        fg = colors.fg,
        fg2 = colors.fg2,
        fg3 = colors.fg3,
        fg4 = colors.fg4,
        red = colors.red,
        green = colors.green,
        yellow = colors.yellow,
        blue = colors.blue,
        blue_bright = colors.blue_bright,
        purple = colors.purple,
        orange = colors.orange,
        cyan = colors.cyan,
        accent = colors.accent,
    )
}

fn render_named_style_scheme(scheme_name: &str, colors: &ColorScheme) -> String {
    render_style_scheme(
        &style_scheme_id(scheme_name),
        &format!("Desktopctl {}", title_case_scheme_name(scheme_name)),
        scheme_name,
        colors,
    )
}

fn render_current_style_scheme(scheme_name: &str, colors: &ColorScheme) -> String {
    render_style_scheme(
        CURRENT_SCHEME_ID,
        &current_style_scheme_name(scheme_name),
        scheme_name,
        colors,
    )
}

fn cleanup_managed_styles(styles_dir: &Path, expected: &HashSet<String>) -> crate::Result<()> {
    for entry in fs::read_dir(styles_dir)? {
        let entry = entry?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }

        let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        if name.starts_with(GENERATED_FILE_PREFIX)
            && name.ends_with(".xml")
            && !expected.contains(name)
        {
            fs::remove_file(path)?;
        }
    }
    Ok(())
}

fn style_scheme_id_for_appearance(
    catalog: &[SchemeEntry],
    current_colors: &ColorScheme,
    desired_appearance: ColorSchemeAppearance,
) -> String {
    match scheme_pair::scheme_for_appearance(catalog, current_colors, desired_appearance) {
        Some(entry) => style_scheme_id(&entry.name),
        None => CURRENT_SCHEME_ID.to_owned(),
    }
}

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<GeneratedContent> {
    Ok(GeneratedContent::text(render_current_style_scheme(
        &state.color_scheme,
        colors,
    )))
}

pub fn persist(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let styles_dir = expand_user_path(STYLES_DIR)?;
    fs::create_dir_all(&styles_dir)?;

    let catalog = scheme_pair::load_scheme_catalog()?;
    let mut expected = HashSet::from([CURRENT_FILE_NAME.to_owned()]);

    for entry in catalog {
        if entry.name == state.color_scheme {
            continue;
        }

        let file_name = style_scheme_file_name(&entry.name);
        let path = styles_dir.join(&file_name);
        atomic_write(
            &path,
            render_named_style_scheme(&entry.name, &entry.colors).as_bytes(),
        )?;
        expected.insert(file_name);
    }

    cleanup_managed_styles(&styles_dir, &expected)
}

pub fn on_apply(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    let catalog = scheme_pair::load_scheme_catalog()?;
    let dark_scheme_id =
        style_scheme_id_for_appearance(&catalog, colors, ColorSchemeAppearance::Dark);
    let light_scheme_id =
        style_scheme_id_for_appearance(&catalog, colors, ColorSchemeAppearance::Light);

    dconf_set(
        "/org/gnome/gedit/preferences/editor/style-scheme-for-dark-theme-variant",
        &format!("'{}'", dark_scheme_id),
    )?;
    dconf_set(
        "/org/gnome/gedit/preferences/editor/style-scheme-for-light-theme-variant",
        &format!("'{}'", light_scheme_id),
    )?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::targets::testsupport::{dummy_colors, dummy_state};

    fn scheme_entry(
        name: &str,
        family: &str,
        variant: &str,
        appearance: ColorSchemeAppearance,
    ) -> SchemeEntry {
        let mut colors = dummy_colors();
        colors.family = family.to_owned();
        colors.variant = variant.to_owned();
        colors.appearance = appearance;
        SchemeEntry {
            name: name.to_owned(),
            colors,
        }
    }

    fn catalog_fixture() -> Vec<SchemeEntry> {
        vec![
            scheme_entry(
                "gruvbox-dark",
                "gruvbox",
                "dark",
                ColorSchemeAppearance::Dark,
            ),
            scheme_entry(
                "gruvbox-light",
                "gruvbox",
                "light",
                ColorSchemeAppearance::Light,
            ),
            scheme_entry(
                "catppuccin-latte",
                "catppuccin",
                "latte",
                ColorSchemeAppearance::Light,
            ),
            scheme_entry(
                "catppuccin-frappe",
                "catppuccin",
                "frappe",
                ColorSchemeAppearance::Dark,
            ),
            scheme_entry(
                "catppuccin-macchiato",
                "catppuccin",
                "macchiato",
                ColorSchemeAppearance::Dark,
            ),
            scheme_entry(
                "catppuccin-mocha",
                "catppuccin",
                "mocha",
                ColorSchemeAppearance::Dark,
            ),
        ]
    }

    fn colors_for_name(catalog: &[SchemeEntry], name: &str) -> ColorScheme {
        catalog
            .iter()
            .find(|entry| entry.name == name)
            .expect("scheme fixture exists")
            .colors
            .clone()
    }

    #[test]
    fn generate_uses_desktopctl_current_alias_and_palette() {
        let output = match generate(&dummy_colors(), &dummy_state()).expect("generate succeeds") {
            GeneratedContent::Text(value) => value,
            GeneratedContent::Commands(_) => panic!("expected text output"),
        };

        assert!(output.contains("style-scheme id=\"desktopctl-current\""));
        assert!(output.contains("_name=\"Desktopctl Current (Gruvbox Dark)\""));
        assert!(output.contains("kind=\"dark\""));
        assert!(output.contains("Generated from desktopctl theme gruvbox-dark"));
        assert!(output.contains("<color name=\"bg\" value=\"#000000\"/>"));
        assert!(output.contains("<style name=\"def:string\" foreground=\"green\"/>"));
    }

    #[test]
    fn style_scheme_id_for_appearance_uses_current_alias_when_current_scheme_matches() {
        let catalog = catalog_fixture();
        let current = colors_for_name(&catalog, "gruvbox-dark");
        assert_eq!(
            style_scheme_id_for_appearance(&catalog, &current, ColorSchemeAppearance::Dark),
            "desktopctl-current"
        );
        assert_eq!(
            style_scheme_id_for_appearance(&catalog, &current, ColorSchemeAppearance::Light),
            "desktopctl-gruvbox-light"
        );
    }

    #[test]
    fn style_scheme_id_for_appearance_uses_dark_fallback_order_for_light_schemes() {
        let catalog = catalog_fixture();
        let current = colors_for_name(&catalog, "catppuccin-latte");
        assert_eq!(
            style_scheme_id_for_appearance(&catalog, &current, ColorSchemeAppearance::Dark),
            "desktopctl-catppuccin-mocha"
        );
    }

    #[test]
    fn style_scheme_id_for_appearance_falls_back_to_current_alias_when_no_pair_exists() {
        let current = scheme_entry(
            "gruvbox-dark",
            "gruvbox",
            "dark",
            ColorSchemeAppearance::Dark,
        )
        .colors;
        let catalog = vec![SchemeEntry {
            name: "gruvbox-dark".to_owned(),
            colors: current.clone(),
        }];
        assert_eq!(
            style_scheme_id_for_appearance(&catalog, &current, ColorSchemeAppearance::Light),
            "desktopctl-current"
        );
    }
}
