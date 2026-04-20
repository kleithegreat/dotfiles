use super::{Assembly, GeneratedContent, TargetMetadata};
use crate::theme::{
    expand_user_path,
    schema::{ColorScheme, ThemeState},
};
use std::{
    collections::HashSet,
    env, fs,
    path::{Path, PathBuf},
};

#[cfg(unix)]
use std::os::unix::fs::symlink;

pub const METADATA: TargetMetadata = TargetMetadata {
    name: "qt",
    assembly: Assembly::Standalone,
    output_path: Some("~/.config/qt6ct/colors/current.conf"),
    base_path: None,
    extra_outputs: &["~/.config/qt5ct/colors/current.conf"],
    managed_paths: &[
        "~/.config/qt6ct/qt6ct.conf",
        "~/.config/qt5ct/qt5ct.conf",
        "~/.config/kdeglobals",
        "~/.local/share/color-schemes/current.colors",
        "~/.config/hypr/hyprqt6engine.conf",
        "~/.config/Kvantum/kvantum.kvconfig",
        "~/.config/Kvantum/GeneratedTheme/",
        "~/.config/katerc",
        "~/.config/kwriterc",
    ],
    state_keys: &[
        "color_scheme",
        "system_font",
        "mono_font",
        "icon_theme",
        "font_size",
        "qt_font_size_offset",
        "mono_font_size",
        "qt_mono_font_size_offset",
    ],
    reload_cmd: None,
    comment: Some(";"),
    sync_safe: true,
};

const QT6CT_CONF: &str = "~/.config/qt6ct/qt6ct.conf";
const QT5CT_CONF: &str = "~/.config/qt5ct/qt5ct.conf";
const KDEGLOBALS: &str = "~/.config/kdeglobals";
const KCOLORSCHEME: &str = "~/.local/share/color-schemes/current.colors";
const HYPRQT6ENGINE_CONF: &str = "~/.config/hypr/hyprqt6engine.conf";
const KVANTUM_THEME_NAME: &str = "GeneratedTheme";
const KVANTUM_CONFIG: &str = "~/.config/Kvantum/kvantum.kvconfig";
const KVANTUM_THEME_DIR: &str = "~/.config/Kvantum/GeneratedTheme";
const KATERC: &str = "~/.config/katerc";
const KWRITERC: &str = "~/.config/kwriterc";

pub fn generate(colors: &ColorScheme, _state: &ThemeState) -> crate::Result<GeneratedContent> {
    let active = vec![
        argb(&colors.fg),
        argb(&colors.bg1),
        argb(&colors.bg3),
        argb(&colors.bg2),
        argb(&colors.bg_dim),
        argb(&colors.bg3),
        argb(&colors.fg),
        argb(&colors.fg),
        argb(&colors.fg),
        argb(&colors.bg),
        argb(&colors.bg1),
        argb(&colors.bg_dim),
        argb(&colors.accent),
        argb(&colors.fg),
        argb(&colors.blue),
        argb(&colors.purple),
        argb(&colors.bg),
        argb(&colors.bg1),
        argb(&colors.fg),
        argb_alpha(&colors.fg4, "80"),
        argb(&colors.accent),
    ];

    let mut disabled = active.clone();
    for index in [0usize, 6, 8, 13] {
        disabled[index] = argb(&colors.fg4);
    }

    let inactive = active.clone();
    let separator = ", ";
    Ok(GeneratedContent::text(format!(
        concat!(
            "[ColorScheme]\n",
            "active_colors={}\n",
            "disabled_colors={}\n",
            "inactive_colors={}\n",
        ),
        active.join(separator),
        disabled.join(separator),
        inactive.join(separator),
    )))
}

pub fn persist(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    for (conf, scheme) in [
        (QT6CT_CONF, METADATA.output_path.expect("qt6 output path")),
        (QT5CT_CONF, METADATA.extra_outputs[0]),
    ] {
        update_qtct_config(
            &expand_user_path(conf)?,
            &expand_user_path(scheme)?.display().to_string(),
        )?;
    }

    update_kdeglobals(colors, state)?;
    write_kcolorscheme(colors)?;
    write_hyprqt6engine_conf(colors, state)?;
    setup_kvantum(colors)?;
    sync_kde_app_configs(colors)?;
    Ok(())
}

fn argb(hex_color: &str) -> String {
    format!("#ff{}", &hex_color[1..])
}

fn argb_alpha(hex_color: &str, alpha: &str) -> String {
    format!("#{alpha}{}", &hex_color[1..])
}

fn rgb(hex_color: &str) -> String {
    format!(
        "{},{},{}",
        u8::from_str_radix(&hex_color[1..3], 16).unwrap(),
        u8::from_str_radix(&hex_color[3..5], 16).unwrap(),
        u8::from_str_radix(&hex_color[5..7], 16).unwrap()
    )
}

fn rgba(hex_color: &str, alpha: &str) -> String {
    format!("{hex_color}{alpha}")
}

fn update_qtct_config(conf_path: &Path, scheme_path: &str) -> crate::Result<()> {
    let mut config = IniFile::from_path(conf_path)?;
    config.ensure_section("Appearance");
    config.set("Appearance", "style", "kvantum");
    config.set("Appearance", "color_scheme_path", scheme_path);
    config.set("Appearance", "custom_palette", "true");

    if let Some(parent) = conf_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(conf_path, config.to_string_with_header(""))?;
    Ok(())
}

fn kde_state_section(section: &str, state: &str) -> String {
    format!("{section}][{state}")
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

    if !config.has_section("General") {
        return;
    }

    let managed_keys = ["ColorScheme", "Name", "shadeSortColumn"];
    let keys = config.option_names("General");
    for key in keys {
        if managed_keys.contains(&key.as_str()) || key.starts_with("Name[") {
            config.remove_option("General", &key);
        }
    }

    if !config.section_has_items("General") {
        config.remove_section("General");
    }
}

fn kde_color_group(
    config: &mut IniFile,
    section: &str,
    bg: String,
    bg_alt: String,
    fg: String,
    fg_inactive: String,
    colors: &ColorScheme,
) {
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

#[derive(Clone)]
struct KdeColorState {
    bg: String,
    bg_alt: String,
    fg: String,
    fg_inactive: String,
}

fn write_kde_color_states(
    config: &mut IniFile,
    section: &str,
    colors: &ColorScheme,
    active: KdeColorState,
    inactive: Option<KdeColorState>,
) {
    kde_color_group(
        config,
        section,
        active.bg.clone(),
        active.bg_alt.clone(),
        active.fg.clone(),
        active.fg_inactive.clone(),
        colors,
    );
    let inactive = inactive.unwrap_or_else(|| KdeColorState {
        bg: active.bg,
        bg_alt: active.bg_alt,
        fg: rgb(&colors.fg2),
        fg_inactive: rgb(&colors.fg3),
    });
    kde_color_group(
        config,
        &kde_state_section(section, "Inactive"),
        inactive.bg,
        inactive.bg_alt,
        inactive.fg,
        inactive.fg_inactive,
        colors,
    );
}

fn apply_kde_colors(config: &mut IniFile, colors: &ColorScheme) {
    clear_managed_kde_sections(config);

    let fg = rgb(&colors.fg);
    let fg_dim = rgb(&colors.fg4);

    write_kde_color_states(
        config,
        "Colors:Window",
        colors,
        KdeColorState {
            bg: rgb(&colors.bg1),
            bg_alt: rgb(&colors.bg2),
            fg: fg.clone(),
            fg_inactive: fg_dim.clone(),
        },
        None,
    );
    write_kde_color_states(
        config,
        "Colors:View",
        colors,
        KdeColorState {
            bg: rgb(&colors.bg),
            bg_alt: rgb(&colors.bg),
            fg: fg.clone(),
            fg_inactive: fg_dim.clone(),
        },
        None,
    );
    write_kde_color_states(
        config,
        "Colors:Button",
        colors,
        KdeColorState {
            bg: rgb(&colors.bg1),
            bg_alt: rgb(&colors.bg2),
            fg: fg.clone(),
            fg_inactive: fg_dim.clone(),
        },
        None,
    );
    write_kde_color_states(
        config,
        "Colors:Selection",
        colors,
        KdeColorState {
            bg: rgb(&colors.accent),
            bg_alt: rgb(&colors.accent),
            fg: fg.clone(),
            fg_inactive: rgb(&colors.fg2),
        },
        Some(KdeColorState {
            bg: rgb(&colors.bg2),
            bg_alt: rgb(&colors.bg2),
            fg: fg.clone(),
            fg_inactive: rgb(&colors.fg3),
        }),
    );
    write_kde_color_states(
        config,
        "Colors:Tooltip",
        colors,
        KdeColorState {
            bg: rgb(&colors.bg1),
            bg_alt: rgb(&colors.bg),
            fg: fg.clone(),
            fg_inactive: fg_dim.clone(),
        },
        None,
    );
    write_kde_color_states(
        config,
        "Colors:Complementary",
        colors,
        KdeColorState {
            bg: rgb(&colors.bg_dim),
            bg_alt: rgb(&colors.bg),
            fg: fg.clone(),
            fg_inactive: fg_dim.clone(),
        },
        None,
    );
    write_kde_color_states(
        config,
        "Colors:Header",
        colors,
        KdeColorState {
            bg: rgb(&colors.bg1),
            bg_alt: rgb(&colors.bg2),
            fg: fg.clone(),
            fg_inactive: fg_dim.clone(),
        },
        None,
    );

    config.ensure_section("General");
    config.set("General", "ColorScheme", "Custom");
    config.set("General", "Name", "Current Theme");
    config.set("General", "shadeSortColumn", "true");

    config.ensure_section("KDE");
    config.set("KDE", "contrast", "4");

    config.ensure_section("WM");
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
        config.ensure_section(section);
        for (key, value) in values {
            config.set(section, key, &value);
        }
    }
}

fn update_kdeglobals(colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let conf_path = expand_user_path(KDEGLOBALS)?;
    let mut config = IniFile::from_path(&conf_path)?;
    apply_kde_colors(&mut config, colors);
    config.ensure_section("Icons");
    config.set("Icons", "Theme", &state.icon_theme);
    if let Some(parent) = conf_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(conf_path, config.to_string_with_header(""))?;
    Ok(())
}

fn write_kcolorscheme(colors: &ColorScheme) -> crate::Result<()> {
    let conf_path = expand_user_path(KCOLORSCHEME)?;
    let mut config = IniFile::default();
    apply_kde_colors(&mut config, colors);
    if let Some(parent) = conf_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(conf_path, config.to_string_with_header(""))?;
    Ok(())
}

fn write_hyprqt6engine_conf(_colors: &ColorScheme, state: &ThemeState) -> crate::Result<()> {
    let conf_path = expand_user_path(HYPRQT6ENGINE_CONF)?;
    let scheme_path = expand_user_path(METADATA.output_path.expect("qt output path"))?;
    let font_size = state.font_size_for(METADATA.name)?;
    let fixed_font_size = state.mono_font_size_for(METADATA.name)?;
    if let Some(parent) = conf_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(
        conf_path,
        format!(
            concat!(
                "theme {{\n",
                "    color_scheme = {}\n",
                "    icon_theme = {}\n",
                "    style = kvantum\n",
                "    font = {}\n",
                "    font_size = {}\n",
                "    font_fixed = {}\n",
                "    font_fixed_size = {}\n",
                "}}\n",
                "\n",
                "misc {{\n",
                "    menus_have_icons = true\n",
                "    single_click_activate = false\n",
                "    shortcuts_for_context_menus = true\n",
                "}}\n",
            ),
            scheme_path.display(),
            state.icon_theme,
            state.system_font,
            font_size,
            state.mono_font,
            fixed_font_size,
        ),
    )?;
    Ok(())
}

fn ktexteditor_color_theme<'a>(colors: &'a ColorScheme) -> &'a str {
    colors.ktexteditor_theme_name()
}

fn sync_ktexteditor_config(
    conf_path: &Path,
    colors: &ColorScheme,
    clear_filetree_shading: bool,
) -> crate::Result<()> {
    let mut config = IniFile::from_path(conf_path)?;
    config.ensure_section("KTextEditor Renderer");
    config.set(
        "KTextEditor Renderer",
        "Auto Color Theme Selection",
        "false",
    );
    config.set(
        "KTextEditor Renderer",
        "Color Theme",
        ktexteditor_color_theme(colors),
    );

    if clear_filetree_shading && config.has_section("filetree") {
        config.set("filetree", "shadingEnabled", "false");
        if config.has_option("filetree", "editShade") {
            config.remove_option("filetree", "editShade");
        }
        if config.has_option("filetree", "viewShade") {
            config.remove_option("filetree", "viewShade");
        }
    }

    if let Some(parent) = conf_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(conf_path, config.to_string_with_header(""))?;
    Ok(())
}

fn sync_kde_app_configs(colors: &ColorScheme) -> crate::Result<()> {
    sync_ktexteditor_config(&expand_user_path(KATERC)?, colors, true)?;
    sync_ktexteditor_config(&expand_user_path(KWRITERC)?, colors, false)?;
    Ok(())
}

fn kvantum_share_dirs() -> Vec<PathBuf> {
    let user = env::var("USER").ok();
    let mut candidates = Vec::new();

    for data_dir in env::var("XDG_DATA_DIRS").unwrap_or_default().split(':') {
        if data_dir.is_empty() {
            continue;
        }
        candidates.push(PathBuf::from(data_dir));
    }

    candidates.extend([
        PathBuf::from(env::var("HOME").unwrap_or_default())
            .join(".nix-profile")
            .join("share"),
        PathBuf::from(env::var("HOME").unwrap_or_default())
            .join(".local")
            .join("state")
            .join("nix")
            .join("profile")
            .join("share"),
        PathBuf::from(env::var("HOME").unwrap_or_default())
            .join(".local")
            .join("state")
            .join("nix")
            .join("profiles")
            .join("profile")
            .join("share"),
        PathBuf::from("/nix/profile/share"),
        PathBuf::from("/nix/var/nix/profiles/default/share"),
        PathBuf::from("/run/current-system/sw/share"),
    ]);

    if let Some(user) = user {
        candidates.push(
            PathBuf::from("/etc/profiles/per-user")
                .join(user)
                .join("share"),
        );
    }

    let mut unique = Vec::new();
    let mut seen = HashSet::new();
    for candidate in candidates {
        if seen.insert(candidate.clone()) {
            unique.push(candidate);
        }
    }
    unique
}

fn find_kvantum_theme_assets(theme_name: &str) -> Option<(PathBuf, PathBuf)> {
    let svg_name = format!("{theme_name}.svg");
    let kvconfig_name = format!("{theme_name}.kvconfig");

    for share_dir in kvantum_share_dirs() {
        let theme_dir = share_dir.join("Kvantum").join(theme_name);
        let svg = theme_dir.join(&svg_name);
        let kvconfig = theme_dir.join(&kvconfig_name);
        if svg.is_file() && kvconfig.is_file() {
            return Some((svg, kvconfig));
        }
    }

    let nix_store = Path::new("/nix/store");
    if nix_store.is_dir() {
        let mut entries = fs::read_dir(nix_store)
            .ok()?
            .filter_map(Result::ok)
            .collect::<Vec<_>>();
        entries.sort_by_key(|entry| entry.file_name());
        for entry in entries {
            let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
                continue;
            };
            if !name.contains("-qtstyleplugin-kvantum") {
                continue;
            }
            let theme_dir = entry.path().join("share").join("Kvantum").join(theme_name);
            let svg = theme_dir.join(&svg_name);
            let kvconfig = theme_dir.join(&kvconfig_name);
            if svg.is_file() && kvconfig.is_file() {
                return Some((svg, kvconfig));
            }
        }
    }

    None
}

fn kvantum_base_theme(colors: &ColorScheme) -> &'static str {
    if colors.is_dark() {
        "KvGnomeDark"
    } else {
        "KvGnome"
    }
}

fn setup_kvantum(colors: &ColorScheme) -> crate::Result<()> {
    let theme_dir = expand_user_path(KVANTUM_THEME_DIR)?;
    fs::create_dir_all(&theme_dir)?;

    let base_theme = kvantum_base_theme(colors);
    let base_assets = find_kvantum_theme_assets(base_theme);
    let source_svg = base_assets.as_ref().map(|(svg, _)| svg);
    let source_kvconfig = base_assets.as_ref().map(|(_, kvconfig)| kvconfig.as_path());

    let kvconfig_path = theme_dir.join(format!("{KVANTUM_THEME_NAME}.kvconfig"));
    fs::write(
        &kvconfig_path,
        generate_kvantum_kvconfig(colors, source_kvconfig)?,
    )?;

    let svg_link = theme_dir.join(format!("{KVANTUM_THEME_NAME}.svg"));
    if let Some(source_svg) = source_svg {
        if svg_link.is_symlink() || svg_link.exists() {
            fs::remove_file(&svg_link)?;
        }
        #[cfg(unix)]
        symlink(source_svg, &svg_link)?;
    } else if !svg_link.exists() {
        eprintln!(
            "  qt: Kvantum SVG for {base_theme} not found (install qtstyleplugin-kvantum and rebuild)"
        );
    }

    let config_path = expand_user_path(KVANTUM_CONFIG)?;
    if let Some(parent) = config_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(
        config_path,
        format!("[General]\ntheme={KVANTUM_THEME_NAME}\n"),
    )?;
    Ok(())
}

fn generate_kvantum_kvconfig(
    colors: &ColorScheme,
    base_kvconfig: Option<&Path>,
) -> crate::Result<String> {
    let mut config = match base_kvconfig {
        Some(path) => IniFile::from_path(path)?,
        None => IniFile::default(),
    };

    for section in ["%General", "GeneralColors", "Hacks"] {
        config.ensure_section(section);
    }

    for (key, value) in [
        ("window.color", colors.bg1.clone()),
        ("inactive.window.color", colors.bg1.clone()),
        ("base.color", colors.bg.clone()),
        ("inactive.base.color", colors.bg.clone()),
        ("alt.base.color", colors.bg.clone()),
        ("inactive.alt.base.color", colors.bg.clone()),
        ("button.color", colors.bg1.clone()),
        ("light.color", colors.bg3.clone()),
        ("mid.light.color", colors.bg2.clone()),
        ("dark.color", colors.bg_dim.clone()),
        ("mid.color", colors.bg1.clone()),
        ("highlight.color", colors.accent.clone()),
        ("inactive.highlight.color", colors.bg2.clone()),
        ("tooltip.base.color", colors.bg1.clone()),
        ("text.color", colors.fg.clone()),
        ("inactive.text.color", rgba(&colors.fg2, "c8")),
        ("window.text.color", colors.fg.clone()),
        ("inactive.window.text.color", rgba(&colors.fg3, "b0")),
        ("button.text.color", colors.fg.clone()),
        ("disabled.text.color", colors.fg4.clone()),
        ("tooltip.text.color", colors.fg.clone()),
        ("highlight.text.color", colors.fg.clone()),
        ("link.color", colors.blue.clone()),
        ("link.visited.color", colors.purple.clone()),
        ("progress.indicator.text.color", colors.fg.clone()),
    ] {
        config.set("GeneralColors", key, &value);
    }

    for (key, value) in [
        ("transparent_dolphin_view", "false"),
        ("transparent_ktitle_label", "true"),
        ("transparent_menutitle", "true"),
    ] {
        config.set("Hacks", key, value);
    }

    for (section, values) in [
        (
            "PanelButtonCommand",
            vec![
                ("text.normal.color", colors.fg.clone()),
                ("text.normal.inactive.color", rgba(&colors.fg2, "c8")),
                ("text.focus.color", colors.fg.clone()),
                ("text.press.color", colors.fg.clone()),
                ("text.toggle.color", colors.fg.clone()),
                ("text.toggle.inactive.color", rgba(&colors.fg2, "c8")),
            ],
        ),
        ("Dock", vec![("text.normal.color", colors.fg.clone())]),
        (
            "DockTitle",
            vec![
                ("text.normal.color", colors.fg.clone()),
                ("text.focus.color", colors.fg.clone()),
            ],
        ),
        (
            "IndicatorSpinBox",
            vec![("text.normal.color", colors.fg.clone())],
        ),
        (
            "RadioButton",
            vec![
                ("text.normal.color", colors.fg.clone()),
                ("text.focus.color", colors.fg.clone()),
            ],
        ),
        (
            "CheckBox",
            vec![
                ("text.normal.color", colors.fg.clone()),
                ("text.focus.color", colors.fg.clone()),
            ],
        ),
        (
            "LineEdit",
            vec![
                ("text.normal.color", colors.fg.clone()),
                ("text.focus.color", colors.fg.clone()),
            ],
        ),
        (
            "ToolboxTab",
            vec![
                ("text.normal.color", rgba(&colors.fg2, "d8")),
                ("text.normal.inactive.color", rgba(&colors.fg3, "c8")),
                ("text.press.color", colors.fg.clone()),
                ("text.press.inactive.color", rgba(&colors.fg2, "c8")),
                ("text.focus.color", colors.fg.clone()),
            ],
        ),
        (
            "Toolbar",
            vec![
                ("text.normal.color", colors.fg.clone()),
                ("text.focus.color", colors.fg.clone()),
            ],
        ),
        (
            "ItemView",
            vec![
                ("text.normal.color", colors.fg.clone()),
                ("text.normal.inactive.color", rgba(&colors.fg2, "c8")),
                ("text.focus.color", colors.fg.clone()),
                ("text.press.color", colors.fg.clone()),
                ("text.toggle.color", colors.fg.clone()),
                ("text.toggle.inactive.color", rgba(&colors.fg2, "eb")),
            ],
        ),
        (
            "Tab",
            vec![
                ("text.normal.color", rgba(&colors.fg3, "c8")),
                ("text.normal.inactive.color", rgba(&colors.fg4, "b0")),
                ("text.focus.color", rgba(&colors.fg2, "e0")),
                ("text.toggle.color", colors.fg.clone()),
            ],
        ),
        (
            "HeaderSection",
            vec![
                ("text.normal.color", rgba(&colors.fg3, "c8")),
                ("text.normal.inactive.color", rgba(&colors.fg4, "b0")),
                ("text.focus.color", rgba(&colors.fg2, "e0")),
                ("text.toggle.color", colors.fg.clone()),
            ],
        ),
        (
            "MenuItem",
            vec![
                ("text.normal.color", colors.fg.clone()),
                ("text.focus.color", colors.fg.clone()),
            ],
        ),
        (
            "MenuBarItem",
            vec![
                ("text.normal.color", colors.fg.clone()),
                ("text.focus.color", colors.fg.clone()),
            ],
        ),
        (
            "TitleBar",
            vec![
                ("text.normal.color", rgba(&colors.fg3, "c8")),
                ("text.focus.color", colors.fg.clone()),
            ],
        ),
    ] {
        config.ensure_section(section);
        for (key, value) in values {
            config.set(section, key, &value);
        }
    }

    Ok(config.to_string_with_header(&format!(
        "; Generated by apply-theme \u{2014} {}-{}\n\n",
        colors.family, colors.variant
    )))
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
        self.sections.iter().any(|section| section.name == name)
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

    fn option_names(&self, section: &str) -> Vec<String> {
        self.section(section)
            .map(|section| section.items.iter().map(|(key, _)| key.clone()).collect())
            .unwrap_or_default()
    }

    fn section_has_items(&self, section: &str) -> bool {
        self.section(section)
            .map(|section| !section.items.is_empty())
            .unwrap_or(false)
    }

    fn has_option(&self, section: &str, key: &str) -> bool {
        self.section(section)
            .map(|section| {
                section
                    .items
                    .iter()
                    .any(|(existing_key, _)| existing_key == key)
            })
            .unwrap_or(false)
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

    fn to_string_with_header(&self, header: &str) -> String {
        let mut output = String::new();
        output.push_str(header);
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
    use super::{ktexteditor_color_theme, kvantum_base_theme};
    use crate::theme::{resolve, schema::ColorScheme};
    use std::path::{Path, PathBuf};

    fn repo_root() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("desktopctl lives under the repo root")
            .to_path_buf()
    }

    fn load_repo_colors(scheme_name: &str) -> ColorScheme {
        resolve::load_colors(scheme_name, &repo_root().join("themes/colors"))
            .expect("repo color scheme should deserialize")
    }

    #[test]
    fn ktexteditor_theme_uses_declared_theme_metadata_or_appearance() {
        assert_eq!(
            ktexteditor_color_theme(&load_repo_colors("gruvbox-dark")),
            "gruvbox Dark"
        );
        assert_eq!(
            ktexteditor_color_theme(&load_repo_colors("gruvbox-light")),
            "gruvbox Light"
        );
        assert_eq!(
            ktexteditor_color_theme(&load_repo_colors("tokyo-night")),
            "Breeze Dark"
        );
        assert_eq!(
            ktexteditor_color_theme(&load_repo_colors("tokyo-night-light")),
            "Breeze Light"
        );
        assert_eq!(
            ktexteditor_color_theme(&load_repo_colors("rose-pine-dawn")),
            "Breeze Light"
        );
    }

    #[test]
    fn kvantum_base_theme_uses_declared_scheme_appearance() {
        assert_eq!(
            kvantum_base_theme(&load_repo_colors("tokyo-night")),
            "KvGnomeDark"
        );
        assert_eq!(
            kvantum_base_theme(&load_repo_colors("tokyo-night-light")),
            "KvGnome"
        );
        assert_eq!(
            kvantum_base_theme(&load_repo_colors("rose-pine-dawn")),
            "KvGnome"
        );
    }
}
