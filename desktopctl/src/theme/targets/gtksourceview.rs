use super::Target;
use crate::{
    cmd::dconf_write_str,
    fs_util::expand_user_path,
    theme::{
        color::readable_on_ends,
        schema::{ColorScheme, ThemeState},
    },
};
use std::{fs, path::Path};

pub const TARGET: Target = Target::standalone(
    "gtksourceview",
    &["color_scheme"],
    "~/.local/share/libgedit-gtksourceview-300/styles/desktopctl-current.xml",
    generate,
)
.persist(persist)
.on_apply(on_apply);

const STYLES_DIR: &str = "~/.local/share/libgedit-gtksourceview-300/styles";
const CURRENT_FILE_NAME: &str = "desktopctl-current.xml";
const CURRENT_SCHEME_ID: &str = "desktopctl-current";
const GENERATED_FILE_PREFIX: &str = "desktopctl-";

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
    let kind = colors.appearance.as_str();
    let on_accent = readable_on_ends(&colors.accent, &colors.bg, &colors.fg);
    let on_red = readable_on_ends(&colors.red, &colors.bg, &colors.fg);
    let on_yellow = readable_on_ends(&colors.yellow, &colors.bg, &colors.fg);

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
            "  <color name=\"on_accent\" value=\"{on_accent}\"/>\n",
            "  <color name=\"on_red\" value=\"{on_red}\"/>\n",
            "  <color name=\"on_yellow\" value=\"{on_yellow}\"/>\n",
            "\n",
            "  <style name=\"text\" foreground=\"fg\" background=\"bg\"/>\n",
            "  <style name=\"selection\" foreground=\"on_accent\" background=\"accent\"/>\n",
            "  <style name=\"cursor\" foreground=\"fg\"/>\n",
            "  <style name=\"secondary-cursor\" foreground=\"fg4\"/>\n",
            "  <style name=\"current-line\" background=\"bg_dim\"/>\n",
            "  <style name=\"line-numbers\" foreground=\"fg4\" background=\"bg_dim\"/>\n",
            "  <style name=\"right-margin\" foreground=\"bg2\" background=\"bg1\"/>\n",
            "  <style name=\"draw-spaces\" foreground=\"fg4\"/>\n",
            "  <style name=\"bracket-match\" foreground=\"bg\" background=\"fg4\"/>\n",
            "  <style name=\"bracket-mismatch\" foreground=\"on_red\" background=\"red\"/>\n",
            "  <style name=\"search-match\" foreground=\"on_yellow\" background=\"yellow\"/>\n",
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
        on_accent = on_accent,
        on_red = on_red,
        on_yellow = on_yellow,
    )
}

fn cleanup_managed_styles(styles_dir: &Path) -> crate::Result<()> {
    for entry in fs::read_dir(styles_dir)? {
        let entry = entry?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }

        let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
            continue;
        };
        if name != CURRENT_FILE_NAME
            && name.starts_with(GENERATED_FILE_PREFIX)
            && name.ends_with(".xml")
        {
            fs::remove_file(path)?;
        }
    }
    Ok(())
}

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> crate::Result<String> {
    Ok(render_style_scheme(
        CURRENT_SCHEME_ID,
        &current_style_scheme_name(&state.color_scheme),
        &state.color_scheme,
        colors,
    ))
}

pub fn persist(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    let styles_dir = expand_user_path(STYLES_DIR)?;
    if !styles_dir.exists() {
        return Ok(());
    }
    cleanup_managed_styles(&styles_dir)
}

pub fn on_apply(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    dconf_write_str(
        "/org/gnome/gedit/preferences/editor/style-scheme-for-dark-theme-variant",
        CURRENT_SCHEME_ID,
    )?;
    dconf_write_str(
        "/org/gnome/gedit/preferences/editor/style-scheme-for-light-theme-variant",
        CURRENT_SCHEME_ID,
    )?;

    Ok(())
}
