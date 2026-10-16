use super::Target;
use crate::theme::{
    color::{blend, readable_on},
    json,
    schema::{ColorScheme, ThemeState},
};
use serde_json::{Map, Value};

/// The filename is T3 Code's theme id; it only shows once that id is selected.
pub const TARGET: Target = Target::standalone(
    "t3code",
    &["color_scheme"],
    "~/.t3/userdata/themes/desktopctl.json",
    generate,
);

/// T3 Code derives every role from the `canvas` and `accent` seeds, tinting
/// surfaces with the accent hue; the overrides pin the neutral ramp and the
/// status colours back to the scheme's own.
pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<String> {
    let status_mix = if colors.is_dark() { 0.16 } else { 0.08 };
    let error_surface = blend(&colors.bg, &colors.red, status_mix);
    let warning_surface = blend(&colors.bg, &colors.yellow, status_mix);
    let overrides = [
        ("text", colors.fg.clone()),
        ("textMuted", colors.fg3.clone()),
        ("secondaryLabel", colors.fg3.clone()),
        ("iconMuted", colors.fg4.clone()),
        ("placeholder", colors.fg4.clone()),
        ("toolbarForeground", colors.fg.clone()),
        ("toolbarControl", colors.bg1.clone()),
        ("toolbarControlForeground", colors.fg.clone()),
        ("toolbarControlHover", colors.bg2.clone()),
        ("toolbarBorder", colors.bg2.clone()),
        ("surface", colors.bg.clone()),
        ("surfaceRaised", colors.bg1.clone()),
        ("surfaceOverlay", colors.bg2.clone()),
        ("border", colors.bg3.clone()),
        ("input", colors.bg3.clone()),
        ("muted", colors.bg1.clone()),
        ("mutedForeground", colors.fg3.clone()),
        ("secondary", colors.bg2.clone()),
        ("secondaryForeground", colors.fg.clone()),
        (
            "accentForeground",
            readable_on(&colors.accent, &[&colors.bg, &colors.fg]),
        ),
        ("error", colors.red.clone()),
        ("errorSurface", error_surface.clone()),
        (
            "errorForeground",
            readable_on(&error_surface, &[&colors.red, &colors.fg]),
        ),
        ("warning", colors.yellow.clone()),
        ("warningSurface", warning_surface.clone()),
        (
            "warningForeground",
            readable_on(&warning_surface, &[&colors.yellow, &colors.fg]),
        ),
        ("codeBackground", colors.bg1.clone()),
        ("codeForeground", colors.fg.clone()),
        ("sidebar", colors.bg_dim.clone()),
        ("sidebarForeground", colors.fg.clone()),
        ("sidebarMutedForeground", colors.fg3.clone()),
        ("sidebarControlSurface", colors.bg1.clone()),
        ("sidebarRowHover", colors.bg1.clone()),
        ("sidebarRowActive", colors.bg2.clone()),
        ("sidebarRowSelected", colors.bg2.clone()),
        ("sidebarBorder", colors.bg2.clone()),
        ("terminalBackground", colors.bg.clone()),
        ("terminalForeground", colors.fg.clone()),
        ("terminalCursor", colors.fg.clone()),
        ("terminalSelection", colors.bg3.clone()),
        ("terminalScrollbar", colors.bg2.clone()),
        ("terminalScrollbarHover", colors.bg3.clone()),
    ]
    .into_iter()
    .map(|(key, value)| (key.to_owned(), Value::String(value)))
    .collect::<Map<_, _>>();

    let appearance = if colors.is_dark() { "dark" } else { "light" };
    let mut root = Map::new();
    root.insert("name".to_owned(), Value::String("desktopctl".to_owned()));
    root.insert(
        "appearance".to_owned(),
        Value::String(appearance.to_owned()),
    );
    root.insert("canvas".to_owned(), Value::String(colors.bg.clone()));
    root.insert("accent".to_owned(), Value::String(colors.accent.clone()));
    root.insert("colors".to_owned(), Value::Object(overrides));

    Ok(format!(
        "{}\n",
        json::format_pretty_value(&Value::Object(root))
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::color::contrast_ratio;
    use crate::theme::targets::testsupport::{REPO_SCHEMES, dummy_state, load_repo_colors};

    fn render(scheme: &str) -> Value {
        serde_json::from_str(
            &generate(&load_repo_colors(scheme), &dummy_state()).expect("generates"),
        )
        .expect("valid json")
    }

    #[test]
    fn appearance_follows_the_scheme() {
        for scheme in REPO_SCHEMES {
            let expected = if load_repo_colors(scheme).is_dark() {
                "dark"
            } else {
                "light"
            };
            assert_eq!(render(scheme)["appearance"], expected, "{scheme}");
        }
    }

    /// T3 Code's server drops the whole file when a seed is not `#rgb`/`#rrggbb`.
    #[test]
    fn every_colour_is_six_digit_hex() {
        for scheme in REPO_SCHEMES {
            let value = render(scheme);
            let seeds = [&value["canvas"], &value["accent"]];
            for colour in seeds
                .into_iter()
                .chain(value["colors"].as_object().expect("colors").values())
            {
                let colour = colour.as_str().expect("string colour");
                assert!(
                    colour.len() == 7
                        && colour.starts_with('#')
                        && colour[1..].chars().all(|c| c.is_ascii_hexdigit()),
                    "{scheme}: {colour}"
                );
            }
        }
    }

    #[test]
    fn foregrounds_on_fills_clear_aa() {
        for scheme in REPO_SCHEMES {
            let value = render(scheme);
            let role = |name: &str| value["colors"][name].as_str().expect(name).to_owned();
            for (plate, ink) in [
                (
                    value["accent"].as_str().expect("accent").to_owned(),
                    role("accentForeground"),
                ),
                (role("errorSurface"), role("errorForeground")),
                (role("warningSurface"), role("warningForeground")),
            ] {
                assert!(
                    contrast_ratio(&plate, &ink) >= 4.5,
                    "{scheme}: {ink} on {plate}"
                );
            }
        }
    }
}
