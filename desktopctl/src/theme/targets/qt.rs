use super::Target;
use crate::theme::{
    atomic_write, color,
    command::run,
    expand_user_path,
    schema::{ColorScheme, ThemeState},
};
use std::{fs, path::Path};

pub const TARGET: Target = Target::hooks(
    "qt",
    &[
        "color_scheme",
        "system_font",
        "mono_font",
        "icon_theme",
        "font_size",
        "qt_font_size_offset",
        "mono_font_size",
        "qt_mono_font_size_offset",
    ],
)
.persist(persist)
.on_apply(on_apply);

const KDEGLOBALS: &str = "~/.config/kdeglobals";
const KATERC: &str = "~/.config/katerc";
const KWRITERC: &str = "~/.config/kwriterc";

/// `KGlobalSettings::ChangeType` values the KDE platform theme acts on.
const PALETTE_CHANGED: &str = "0";
const ICON_CHANGED: &str = "4";

pub fn persist(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    update_kdeglobals(colors, state)?;
    sync_ktexteditor_config(&expand_user_path(KATERC)?, colors, true)?;
    sync_ktexteditor_config(&expand_user_path(KWRITERC)?, colors, false)?;
    Ok(())
}

/// Running Qt apps re-read kdeglobals on these session-bus signals.
pub fn on_apply(_colors: &ColorScheme, _state: &ThemeState) -> crate::Result<()> {
    for change in [PALETTE_CHANGED, ICON_CHANGED] {
        run(&[
            "busctl",
            "--user",
            "emit",
            "/KGlobalSettings",
            "org.kde.KGlobalSettings",
            "notifyChange",
            "ii",
            change,
            "0",
        ])?;
    }
    run(&[
        "busctl",
        "--user",
        "emit",
        "/KDEPlatformTheme",
        "org.kde.KDEPlatformTheme",
        "refreshFonts",
    ])
}

fn rgb(hex_color: &str) -> String {
    let [red, green, blue] = color::parse_hex(hex_color).expect("scheme colors are validated");
    format!("{red},{green},{blue}")
}

/// `QFont::toString()`'s 16-field form. A field count Qt cannot parse makes
/// `fromString` fail silently and the default font survive.
fn qfont(family: &str, size: i64) -> String {
    format!("{family},{size},-1,5,400,0,0,0,0,0,0,0,0,0,0,1")
}

fn clear_managed_kde_sections(config: &mut IniFile) {
    let sections = config
        .section_names()
        .into_iter()
        .filter(|section| {
            section.starts_with("Colors:")
                || section.starts_with("ColorEffects:")
                || matches!(section.as_str(), "KDE" | "WM")
        })
        .collect::<Vec<_>>();
    for section in sections {
        config.remove_section(&section);
    }
}

/// `[bg, bg_alt, fg, fg_inactive]` plus the roles every group shares.
fn kde_color_group(config: &mut IniFile, section: &str, roles: [String; 4], colors: &ColorScheme) {
    let [bg, bg_alt, fg, fg_inactive] = roles;
    config.ensure_section(section);
    for (key, value) in [
        ("BackgroundNormal", bg),
        ("BackgroundAlternate", bg_alt),
        ("ForegroundNormal", fg),
        ("ForegroundInactive", fg_inactive),
        ("ForegroundActive", rgb(&colors.accent)),
        ("ForegroundLink", rgb(&colors.blue)),
        ("ForegroundVisited", rgb(&colors.purple)),
        ("ForegroundNegative", rgb(&colors.red)),
        ("ForegroundNeutral", rgb(&colors.yellow)),
        ("ForegroundPositive", rgb(&colors.green)),
        ("DecorationFocus", rgb(&colors.accent)),
        ("DecorationHover", rgb(&colors.accent)),
    ] {
        config.set(section, key, &value);
    }
}

fn apply_kde_colors(config: &mut IniFile, colors: &ColorScheme) {
    clear_managed_kde_sections(config);

    let fg = rgb(&colors.fg);
    let on_accent = color::readable_on_ends(&colors.accent, &colors.bg, &colors.fg);
    let normal = |bg: &str, bg_alt: &str| {
        let active = [rgb(bg), rgb(bg_alt), fg.clone(), rgb(&colors.fg4)];
        let inactive = [rgb(bg), rgb(bg_alt), rgb(&colors.fg2), rgb(&colors.fg3)];
        (active, inactive)
    };
    let selection = (
        [
            rgb(&colors.accent),
            rgb(&colors.accent),
            rgb(&on_accent),
            rgb(&colors.fg2),
        ],
        [
            rgb(&colors.bg2),
            rgb(&colors.bg2),
            fg.clone(),
            rgb(&colors.fg3),
        ],
    );
    for (section, (active, inactive)) in [
        ("Colors:Window", normal(&colors.bg1, &colors.bg2)),
        ("Colors:View", normal(&colors.bg, &colors.bg)),
        ("Colors:Button", normal(&colors.bg1, &colors.bg2)),
        ("Colors:Selection", selection),
        ("Colors:Tooltip", normal(&colors.bg1, &colors.bg)),
        ("Colors:Complementary", normal(&colors.bg_dim, &colors.bg)),
        ("Colors:Header", normal(&colors.bg1, &colors.bg2)),
    ] {
        kde_color_group(config, section, active, colors);
        kde_color_group(config, &format!("{section}][Inactive"), inactive, colors);
    }

    config.set("General", "shadeSortColumn", "true");
    config.set("KDE", "contrast", "4");

    config.set("WM", "activeBackground", &rgb(&colors.bg1));
    config.set("WM", "activeForeground", &fg);
    config.set("WM", "inactiveBackground", &rgb(&colors.bg1));
    config.set("WM", "inactiveForeground", &rgb(&colors.fg2));

    for (section, values) in [
        (
            "ColorEffects:Disabled",
            vec![
                ("Color", rgb(&colors.bg3)),
                ("ColorAmount", "0".to_owned()),
                ("ColorEffect", "0".to_owned()),
                ("ContrastAmount", "0.65".to_owned()),
                ("ContrastEffect", "1".to_owned()),
                ("IntensityAmount", "0.1".to_owned()),
                ("IntensityEffect", "2".to_owned()),
            ],
        ),
        (
            "ColorEffects:Inactive",
            vec![
                ("ChangeSelectionColor", "true".to_owned()),
                ("Color", rgb(&colors.bg3)),
                ("ColorAmount", "0.025".to_owned()),
                ("ColorEffect", "2".to_owned()),
                ("ContrastAmount", "0.1".to_owned()),
                ("ContrastEffect", "2".to_owned()),
                ("Enable", "false".to_owned()),
                ("IntensityAmount", "0".to_owned()),
                ("IntensityEffect", "0".to_owned()),
            ],
        ),
    ] {
        for (key, value) in values {
            config.set(section, key, &value);
        }
    }
}

fn apply_kde_fonts(config: &mut IniFile, state: &ThemeState) -> crate::Result<()> {
    let size = state.font_size_for(TARGET.name)?;
    let ui = qfont(&state.system_font, size);
    for key in ["font", "menuFont", "toolBarFont"] {
        config.set("General", key, &ui);
    }
    config.set(
        "General",
        "smallestReadableFont",
        &qfont(&state.system_font, size - 2),
    );
    config.set(
        "General",
        "fixed",
        &qfont(&state.mono_font, state.mono_font_size_for(TARGET.name)?),
    );
    Ok(())
}

fn update_kdeglobals(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let conf_path = expand_user_path(KDEGLOBALS)?;
    let mut config = IniFile::from_path(&conf_path)?;
    apply_kde_colors(&mut config, colors);
    apply_kde_fonts(&mut config, state)?;
    config.set("Icons", "Theme", kde_icon_theme(&state.icon_theme));
    atomic_write(&conf_path, config.render().as_bytes())?;
    Ok(())
}

fn kde_icon_theme(theme: &str) -> &str {
    match theme {
        "Neuwaita" => "Neuwaita-KDE",
        _ => theme,
    }
}

fn sync_ktexteditor_config(
    conf_path: &Path,
    colors: &ColorScheme,
    clear_filetree_shading: bool,
) -> crate::Result<()> {
    let mut config = IniFile::from_path(conf_path)?;
    config.set(
        "KTextEditor Renderer",
        "Auto Color Theme Selection",
        "false",
    );
    config.set(
        "KTextEditor Renderer",
        "Color Theme",
        colors.ktexteditor_theme_name(),
    );

    if clear_filetree_shading && config.has_section("filetree") {
        config.set("filetree", "shadingEnabled", "false");
        config.remove_option("filetree", "editShade");
        config.remove_option("filetree", "viewShade");
    }

    atomic_write(conf_path, config.render().as_bytes())?;
    Ok(())
}

#[derive(Clone, Default)]
struct IniFile {
    sections: Vec<IniSection>,
}

#[derive(Clone)]
struct IniSection {
    name: String,
    items: Vec<(String, String)>,
}

impl IniFile {
    fn from_path(path: &Path) -> crate::Result<Self> {
        if !path.is_file() {
            return Ok(Self::default());
        }
        Ok(Self::parse(&fs::read_to_string(path)?))
    }

    fn parse(contents: &str) -> Self {
        let mut ini = Self::default();
        let mut current_section = None;

        for line in contents.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with(';') {
                continue;
            }

            if trimmed.starts_with('[') && trimmed.ends_with(']') {
                let name = trimmed[1..trimmed.len() - 1].to_owned();
                current_section = Some(ini.ensure_section(&name));
                continue;
            }

            let Some(section_index) = current_section else {
                continue;
            };

            let delimiter = trimmed.find('=').or_else(|| trimmed.find(':'));
            let Some(delimiter) = delimiter else {
                continue;
            };

            let key = trimmed[..delimiter].trim();
            let value = trimmed[delimiter + 1..].trim();
            ini.set_by_index(section_index, key, value);
        }

        ini
    }

    fn ensure_section(&mut self, name: &str) -> usize {
        if let Some(index) = self
            .sections
            .iter()
            .position(|section| section.name == name)
        {
            index
        } else {
            self.sections.push(IniSection {
                name: name.to_owned(),
                items: Vec::new(),
            });
            self.sections.len() - 1
        }
    }

    fn has_section(&self, name: &str) -> bool {
        self.section(name).is_some()
    }

    fn remove_section(&mut self, name: &str) {
        self.sections.retain(|section| section.name != name);
    }

    fn section_names(&self) -> Vec<String> {
        self.sections
            .iter()
            .map(|section| section.name.clone())
            .collect()
    }

    fn set(&mut self, section: &str, key: &str, value: &str) {
        let index = self.ensure_section(section);
        self.set_by_index(index, key, value);
    }

    fn set_by_index(&mut self, section_index: usize, key: &str, value: &str) {
        let section = &mut self.sections[section_index];
        if let Some((_, existing_value)) = section
            .items
            .iter_mut()
            .find(|(existing_key, _)| existing_key == key)
        {
            *existing_value = value.to_owned();
        } else {
            section.items.push((key.to_owned(), value.to_owned()));
        }
    }

    fn remove_option(&mut self, section: &str, key: &str) {
        if let Some(section) = self.section_mut(section) {
            section
                .items
                .retain(|(existing_key, _)| existing_key != key);
        }
    }

    fn render(&self) -> String {
        let mut output = String::new();
        for section in &self.sections {
            output.push('[');
            output.push_str(&section.name);
            output.push_str("]\n");
            for (key, value) in &section.items {
                output.push_str(key);
                output.push('=');
                output.push_str(value);
                output.push('\n');
            }
            output.push('\n');
        }
        output
    }

    fn section(&self, name: &str) -> Option<&IniSection> {
        self.sections.iter().find(|section| section.name == name)
    }

    fn section_mut(&mut self, name: &str) -> Option<&mut IniSection> {
        self.sections
            .iter_mut()
            .find(|section| section.name == name)
    }
}

#[cfg(test)]
mod tests {
    use super::{IniFile, apply_kde_colors, kde_icon_theme};
    use crate::theme::{
        color::contrast_ratio,
        targets::testsupport::{REPO_SCHEMES, load_repo_colors},
    };

    #[test]
    fn selected_text_is_readable_on_the_highlight() {
        for scheme in REPO_SCHEMES {
            let mut config = IniFile::default();
            apply_kde_colors(&mut config, &load_repo_colors(scheme));
            let role = |key: &str| {
                let section = config.section("Colors:Selection").expect("selection group");
                let (_, value) = section
                    .items
                    .iter()
                    .find(|(name, _)| name == key)
                    .expect("role present");
                let channels = value
                    .split(',')
                    .map(|channel| channel.parse::<u8>().expect("channel"))
                    .collect::<Vec<_>>();
                format!("#{:02x}{:02x}{:02x}", channels[0], channels[1], channels[2])
            };
            let ratio = contrast_ratio(&role("BackgroundNormal"), &role("ForegroundNormal"));
            assert!(ratio >= 4.5, "{scheme}: {ratio:.2}");
        }
    }

    #[test]
    fn ktexteditor_theme_uses_declared_theme_metadata_or_appearance() {
        assert_eq!(
            load_repo_colors("gruvbox-dark").ktexteditor_theme_name(),
            "gruvbox Dark"
        );
        assert_eq!(
            load_repo_colors("gruvbox-light").ktexteditor_theme_name(),
            "gruvbox Light"
        );
        assert_eq!(
            load_repo_colors("tokyo-night").ktexteditor_theme_name(),
            "Tokyo Night"
        );
        assert_eq!(
            load_repo_colors("tokyo-night-light").ktexteditor_theme_name(),
            "Tokyo Night Light"
        );
        assert_eq!(
            load_repo_colors("rose-pine").ktexteditor_theme_name(),
            "Breeze Dark"
        );
        assert_eq!(
            load_repo_colors("rose-pine-dawn").ktexteditor_theme_name(),
            "Breeze Light"
        );
    }

    #[test]
    fn kde_icon_theme_uses_kde_specific_neuwaita_wrapper() {
        assert_eq!(kde_icon_theme("Neuwaita"), "Neuwaita-KDE");
        assert_eq!(kde_icon_theme("Papirus-Dark"), "Papirus-Dark");
    }
}
