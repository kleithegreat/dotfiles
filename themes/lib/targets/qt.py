"""Qt6ct/qt5ct color scheme, KDE color globals, hyprqt6engine, and Kvantum generator."""

import configparser
import io
import os
import sys
from pathlib import Path

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "qt"
ASSEMBLY = "standalone"
OUTPUT_PATH = "~/.config/qt6ct/colors/current.conf"
EXTRA_OUTPUTS = ["~/.config/qt5ct/colors/current.conf"]
RELOAD_CMD = None
COMMENT = ";"

_QT6CT_CONF = "~/.config/qt6ct/qt6ct.conf"
_QT5CT_CONF = "~/.config/qt5ct/qt5ct.conf"
_KDEGLOBALS = "~/.config/kdeglobals"
_KCOLORSCHEME = "~/.local/share/color-schemes/current.colors"
_HYPRQT6ENGINE_CONF = "~/.config/hypr/hyprqt6engine.conf"
_KVANTUM_THEME_NAME = "GeneratedTheme"
_KVANTUM_CONFIG = "~/.config/Kvantum/kvantum.kvconfig"
_KVANTUM_THEME_DIR = f"~/.config/Kvantum/{_KVANTUM_THEME_NAME}"
_KATERC = "~/.config/katerc"
_KWRITERC = "~/.config/kwriterc"


def _new_config() -> configparser.RawConfigParser:
    config = configparser.RawConfigParser(strict=False)
    config.optionxform = str
    return config


def _argb(hex_color: str) -> str:
    """'#rrggbb' -> '#ffrrggbb' (full opacity)."""
    return f"#ff{hex_color[1:]}"


def _argb_alpha(hex_color: str, alpha: str = "80") -> str:
    """'#rrggbb' -> '#AArrggbb'."""
    return f"#{alpha}{hex_color[1:]}"


def _rgb(hex_color: str) -> str:
    """'#rrggbb' -> 'r,g,b' decimal for KDE config."""
    return f"{int(hex_color[1:3], 16)},{int(hex_color[3:5], 16)},{int(hex_color[5:7], 16)}"


def _rgba(hex_color: str, alpha: str) -> str:
    """'#rrggbb' -> '#rrggbbaa' for Kvantum's inactive text roles."""
    return f"{hex_color}{alpha}"


def _serialize_config(config: configparser.RawConfigParser, header: str = "") -> str:
    buffer = io.StringIO()
    if header:
        buffer.write(header)
    config.write(buffer, space_around_delimiters=False)
    return buffer.getvalue()


def generate(colors: ColorScheme, state: ThemeState) -> str:
    # QPalette color roles (21 values, Qt5/Qt6 order):
    #  0 WindowText       6 Text          12 Highlight        17 ToolTipBase
    #  1 Button           7 BrightText    13 HighlightedText  18 ToolTipText
    #  2 Light            8 ButtonText    14 Link             19 PlaceholderText
    #  3 Midlight         9 Base          15 LinkVisited      20 Accent
    #  4 Dark            10 Window        16 AlternateBase
    #  5 Mid             11 Shadow
    active = [
        _argb(colors.fg),        #  0 WindowText
        _argb(colors.bg1),       #  1 Button
        _argb(colors.bg3),       #  2 Light
        _argb(colors.bg2),       #  3 Midlight
        _argb(colors.bg_dim),    #  4 Dark
        _argb(colors.bg3),       #  5 Mid
        _argb(colors.fg),        #  6 Text
        _argb(colors.fg),        #  7 BrightText
        _argb(colors.fg),        #  8 ButtonText
        _argb(colors.bg),        #  9 Base
        _argb(colors.bg1),       # 10 Window
        _argb(colors.bg_dim),    # 11 Shadow
        _argb(colors.accent),    # 12 Highlight
        _argb(colors.fg),        # 13 HighlightedText
        _argb(colors.blue),      # 14 Link
        _argb(colors.purple),    # 15 LinkVisited
        _argb(colors.bg),        # 16 AlternateBase
        _argb(colors.bg1),       # 17 ToolTipBase
        _argb(colors.fg),        # 18 ToolTipText
        _argb_alpha(colors.fg4), # 19 PlaceholderText
        _argb(colors.accent),    # 20 Accent
    ]

    disabled = list(active)
    for i in (0, 6, 8, 13):  # Mute text roles
        disabled[i] = _argb(colors.fg4)

    inactive = list(active)

    sep = ", "
    return (
        "[ColorScheme]\n"
        f"active_colors={sep.join(active)}\n"
        f"disabled_colors={sep.join(disabled)}\n"
        f"inactive_colors={sep.join(inactive)}\n"
    )


def persist(colors: ColorScheme, state: ThemeState) -> None:
    """Update qt6ct/qt5ct configs, KDE globals, KColorScheme, hyprqt6engine, and Kvantum."""
    for conf, scheme in [
        (_QT6CT_CONF, OUTPUT_PATH),
        (_QT5CT_CONF, EXTRA_OUTPUTS[0]),
    ]:
        _update_qtct_config(
            Path(conf).expanduser(),
            str(Path(scheme).expanduser()),
        )
    _update_kdeglobals(colors)
    _write_kcolorscheme(colors)
    _write_hyprqt6engine_conf(colors, state)
    _setup_kvantum(colors)
    _sync_kde_app_configs(colors)


def _update_qtct_config(conf_path: Path, scheme_path: str) -> None:
    """Set style, color_scheme_path, and custom_palette in a qt*ct.conf."""
    config = _new_config()
    if conf_path.is_file():
        config.read(str(conf_path))
    if not config.has_section("Appearance"):
        config.add_section("Appearance")
    config.set("Appearance", "style", "kvantum")
    config.set("Appearance", "color_scheme_path", scheme_path)
    config.set("Appearance", "custom_palette", "true")
    conf_path.parent.mkdir(parents=True, exist_ok=True)
    with open(conf_path, "w") as f:
        config.write(f, space_around_delimiters=False)


def _kde_state_section(section: str, state: str) -> str:
    return f"{section}][{state}"


def _clear_managed_kde_sections(config: configparser.RawConfigParser) -> None:
    """Remove only the theme-managed KDE sections, preserving non-theme settings."""
    for section in list(config.sections()):
        if section.startswith("Colors:") or section.startswith("ColorEffects:") or section in {"KDE", "WM"}:
            config.remove_section(section)

    if not config.has_section("General"):
        return

    managed_keys = {"ColorScheme", "Name", "shadeSortColumn"}
    for key in list(config["General"]):
        if key in managed_keys or key.startswith("Name["):
            config.remove_option("General", key)

    if not config.items("General"):
        config.remove_section("General")


def _kde_color_group(config: configparser.RawConfigParser, section: str,
                     bg: str, bg_alt: str, fg: str, fg_inactive: str,
                     colors: ColorScheme) -> None:
    """Write a full KDE color group section."""
    if not config.has_section(section):
        config.add_section(section)
    vals = {
        "BackgroundNormal": bg,
        "BackgroundAlternate": bg_alt,
        "ForegroundNormal": fg,
        "ForegroundInactive": fg_inactive,
        "ForegroundActive": _rgb(colors.accent),
        "ForegroundLink": _rgb(colors.blue),
        "ForegroundVisited": _rgb(colors.purple),
        "ForegroundNegative": _rgb(colors.red),
        "ForegroundNeutral": _rgb(colors.yellow),
        "ForegroundPositive": _rgb(colors.green),
        "DecorationFocus": _rgb(colors.accent),
        "DecorationHover": _rgb(colors.accent),
    }
    for key, value in vals.items():
        config.set(section, key, value)


def _write_kde_color_states(
    config: configparser.RawConfigParser,
    section: str,
    bg: str,
    bg_alt: str,
    fg: str,
    fg_inactive: str,
    colors: ColorScheme,
    *,
    inactive_bg: str | None = None,
    inactive_bg_alt: str | None = None,
    inactive_fg: str | None = None,
    inactive_fg_inactive: str | None = None,
) -> None:
    _kde_color_group(config, section, bg, bg_alt, fg, fg_inactive, colors)
    _kde_color_group(
        config,
        _kde_state_section(section, "Inactive"),
        inactive_bg or bg,
        inactive_bg_alt or bg_alt,
        inactive_fg or _rgb(colors.fg2),
        inactive_fg_inactive or _rgb(colors.fg3),
        colors,
    )


def _apply_kde_colors(config: configparser.RawConfigParser,
                      colors: ColorScheme) -> None:
    """Write all KDE color sections to a configparser instance."""
    _clear_managed_kde_sections(config)

    fg = _rgb(colors.fg)
    fg_dim = _rgb(colors.fg4)

    # Window: main window chrome (toolbars, sidebars, menubars)
    _write_kde_color_states(
        config,
        "Colors:Window",
        _rgb(colors.bg1),
        _rgb(colors.bg2),
        fg,
        fg_dim,
        colors,
    )
    # View: content areas (file lists, text edits, tree views)
    _write_kde_color_states(
        config,
        "Colors:View",
        _rgb(colors.bg),
        _rgb(colors.bg),
        fg,
        fg_dim,
        colors,
    )
    # Button: buttons and button-like controls
    _write_kde_color_states(
        config,
        "Colors:Button",
        _rgb(colors.bg1),
        _rgb(colors.bg2),
        fg,
        fg_dim,
        colors,
    )
    # Selection: highlighted/selected items
    _write_kde_color_states(
        config,
        "Colors:Selection",
        _rgb(colors.accent),
        _rgb(colors.accent),
        fg,
        _rgb(colors.fg2),
        colors,
        inactive_bg=_rgb(colors.bg2),
        inactive_bg_alt=_rgb(colors.bg2),
        inactive_fg=fg,
        inactive_fg_inactive=_rgb(colors.fg3),
    )
    # Tooltip: popup tooltips
    _write_kde_color_states(
        config,
        "Colors:Tooltip",
        _rgb(colors.bg1),
        _rgb(colors.bg),
        fg,
        fg_dim,
        colors,
    )
    # Complementary: header bars, panel backgrounds
    _write_kde_color_states(
        config,
        "Colors:Complementary",
        _rgb(colors.bg_dim),
        _rgb(colors.bg),
        fg,
        fg_dim,
        colors,
    )
    # Header: column headers, title bars
    _write_kde_color_states(
        config,
        "Colors:Header",
        _rgb(colors.bg1),
        _rgb(colors.bg2),
        fg,
        fg_dim,
        colors,
    )

    # General
    if not config.has_section("General"):
        config.add_section("General")
    config.set("General", "ColorScheme", "Custom")
    config.set("General", "Name", "Current Theme")
    config.set("General", "shadeSortColumn", "true")

    # KDE contrast
    if not config.has_section("KDE"):
        config.add_section("KDE")
    config.set("KDE", "contrast", "4")

    # Window manager colors
    if not config.has_section("WM"):
        config.add_section("WM")
    config.set("WM", "activeBackground", _rgb(colors.bg1))
    config.set("WM", "activeForeground", fg)
    config.set("WM", "inactiveBackground", _rgb(colors.bg1))
    config.set("WM", "inactiveForeground", _rgb(colors.fg2))

    # Color effects (match Breeze Dark behavior)
    for section, vals in {
        "ColorEffects:Disabled": {
            "Color": _rgb(colors.bg3),
            "ColorAmount": "0",
            "ColorEffect": "0",
            "ContrastAmount": "0.65",
            "ContrastEffect": "1",
            "IntensityAmount": "0.1",
            "IntensityEffect": "2",
        },
        "ColorEffects:Inactive": {
            "ChangeSelectionColor": "true",
            "Color": _rgb(colors.bg3),
            "ColorAmount": "0.025",
            "ColorEffect": "2",
            "ContrastAmount": "0.1",
            "ContrastEffect": "2",
            "Enable": "false",
            "IntensityAmount": "0",
            "IntensityEffect": "0",
        },
    }.items():
        if not config.has_section(section):
            config.add_section(section)
        for key, value in vals.items():
            config.set(section, key, value)


def _update_kdeglobals(colors: ColorScheme) -> None:
    """Write KDE color groups to ~/.config/kdeglobals."""
    conf_path = Path(_KDEGLOBALS).expanduser()
    config = _new_config()
    if conf_path.is_file():
        config.read(str(conf_path))
    _apply_kde_colors(config, colors)
    conf_path.parent.mkdir(parents=True, exist_ok=True)
    with open(conf_path, "w") as f:
        config.write(f, space_around_delimiters=False)


def _write_kcolorscheme(colors: ColorScheme) -> None:
    """Write a standalone KColorScheme .colors file for hyprqt6engine."""
    conf_path = Path(_KCOLORSCHEME).expanduser()
    conf_path.parent.mkdir(parents=True, exist_ok=True)
    config = _new_config()
    _apply_kde_colors(config, colors)
    with open(conf_path, "w") as f:
        config.write(f, space_around_delimiters=False)


def _write_hyprqt6engine_conf(colors: ColorScheme, state: ThemeState) -> None:
    """Write hyprqt6engine.conf (hyprlang format) pointing to the qt6ct palette."""
    conf_path = Path(_HYPRQT6ENGINE_CONF).expanduser()
    scheme_path = str(Path(OUTPUT_PATH).expanduser())
    fixed_font_size = state.mono_font_size_for(TARGET_NAME)
    conf_path.parent.mkdir(parents=True, exist_ok=True)
    with open(conf_path, "w") as f:
        f.write(
            f"theme {{\n"
            f"    color_scheme = {scheme_path}\n"
            f"    icon_theme = {state.icon_theme}\n"
            f"    style = kvantum\n"
            f"    font = {state.system_font}\n"
            f"    font_size = {state.font_size}\n"
            f"    font_fixed = {state.mono_font}\n"
            f"    font_fixed_size = {fixed_font_size}\n"
            f"}}\n"
            f"\n"
            f"misc {{\n"
            f"    menus_have_icons = true\n"
            f"    single_click_activate = false\n"
            f"    shortcuts_for_context_menus = true\n"
            f"}}\n"
        )


def _ktexteditor_color_theme(colors: ColorScheme) -> str:
    return "Breeze Dark" if colors.variant == "dark" else "Breeze Light"


def _sync_ktexteditor_config(conf_path: Path, colors: ColorScheme, *, clear_filetree_shading: bool) -> None:
    config = _new_config()
    if conf_path.is_file():
        config.read(str(conf_path))

    if not config.has_section("KTextEditor Renderer"):
        config.add_section("KTextEditor Renderer")
    config.set("KTextEditor Renderer", "Auto Color Theme Selection", "false")
    config.set("KTextEditor Renderer", "Color Theme", _ktexteditor_color_theme(colors))

    if clear_filetree_shading and config.has_section("filetree"):
        config.set("filetree", "shadingEnabled", "false")
        for key in ("editShade", "viewShade"):
            if config.has_option("filetree", key):
                config.remove_option("filetree", key)

    conf_path.parent.mkdir(parents=True, exist_ok=True)
    with open(conf_path, "w") as f:
        config.write(f, space_around_delimiters=False)


def _sync_kde_app_configs(colors: ColorScheme) -> None:
    _sync_ktexteditor_config(Path(_KATERC).expanduser(), colors, clear_filetree_shading=True)
    _sync_ktexteditor_config(Path(_KWRITERC).expanduser(), colors, clear_filetree_shading=False)


def _kvantum_share_dirs() -> list[Path]:
    """Return share dirs that may contain Kvantum theme assets on NixOS."""
    user = os.environ.get("USER")
    candidates: list[Path] = []

    for data_dir in os.environ.get("XDG_DATA_DIRS", "").split(":"):
        if not data_dir:
            continue
        candidates.append(Path(data_dir))

    candidates.extend([
        Path.home() / ".nix-profile" / "share",
        Path.home() / ".local" / "state" / "nix" / "profile" / "share",
        Path.home() / ".local" / "state" / "nix" / "profiles" / "profile" / "share",
        Path("/nix/profile/share"),
        Path("/nix/var/nix/profiles/default/share"),
        Path("/run/current-system/sw/share"),
    ])
    if user:
        candidates.append(Path("/etc/profiles/per-user") / user / "share")

    unique: list[Path] = []
    seen: set[Path] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        unique.append(candidate)
    return unique


def _find_kvantum_theme_assets(theme_name: str) -> tuple[Path, Path] | None:
    """Find both the SVG and kvconfig for an installed Kvantum theme."""
    svg_name = f"{theme_name}.svg"
    kvconfig_name = f"{theme_name}.kvconfig"

    for share_dir in _kvantum_share_dirs():
        theme_dir = share_dir / "Kvantum" / theme_name
        svg = theme_dir / svg_name
        kvconfig = theme_dir / kvconfig_name
        if svg.is_file() and kvconfig.is_file():
            return svg, kvconfig

    nix_store = Path("/nix/store")
    if nix_store.is_dir():
        pattern = f"*-qtstyleplugin-kvantum*/share/Kvantum/{theme_name}"
        for theme_dir in sorted(nix_store.glob(pattern)):
            svg = theme_dir / svg_name
            kvconfig = theme_dir / kvconfig_name
            if svg.is_file() and kvconfig.is_file():
                return svg, kvconfig

    return None


def _setup_kvantum(colors: ColorScheme) -> None:
    """Generate and install a custom Kvantum theme with colors from the scheme."""
    theme_dir = Path(_KVANTUM_THEME_DIR).expanduser()
    theme_dir.mkdir(parents=True, exist_ok=True)

    base_theme = "KvGnomeDark" if colors.variant == "dark" else "KvGnome"
    base_assets = _find_kvantum_theme_assets(base_theme)
    source_svg = base_assets[0] if base_assets else None
    source_kvconfig = base_assets[1] if base_assets else None

    # Write kvconfig with our mapped colors
    kvconfig_path = theme_dir / f"{_KVANTUM_THEME_NAME}.kvconfig"
    kvconfig_path.write_text(_generate_kvantum_kvconfig(colors, source_kvconfig))

    # Symlink SVG from the best matching installed Kvantum base theme
    svg_link = theme_dir / f"{_KVANTUM_THEME_NAME}.svg"
    if source_svg is not None:
        if svg_link.is_symlink() or svg_link.exists():
            svg_link.unlink()
        svg_link.symlink_to(source_svg)
    elif not svg_link.exists():
        print(
            f"  qt: Kvantum SVG for {base_theme} not found "
            f"(install qtstyleplugin-kvantum and rebuild)",
            file=sys.stderr,
        )

    # Write the Kvantum theme selector
    config_path = Path(_KVANTUM_CONFIG).expanduser()
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(f"[General]\ntheme={_KVANTUM_THEME_NAME}\n")


def _generate_kvantum_kvconfig(colors: ColorScheme, base_kvconfig: Path | None) -> str:
    """Generate a Kvantum .kvconfig by overriding the base theme's palette."""
    config = _new_config()
    if base_kvconfig is not None:
        config.read(str(base_kvconfig))

    for section in ("%General", "GeneralColors", "Hacks"):
        if not config.has_section(section):
            config.add_section(section)

    for key, value in {
        "window.color": colors.bg1,
        "inactive.window.color": colors.bg1,
        "base.color": colors.bg,
        "inactive.base.color": colors.bg,
        "alt.base.color": colors.bg,
        "inactive.alt.base.color": colors.bg,
        "button.color": colors.bg1,
        "light.color": colors.bg3,
        "mid.light.color": colors.bg2,
        "dark.color": colors.bg_dim,
        "mid.color": colors.bg1,
        "highlight.color": colors.accent,
        "inactive.highlight.color": colors.bg2,
        "tooltip.base.color": colors.bg1,
        "text.color": colors.fg,
        "inactive.text.color": _rgba(colors.fg2, "c8"),
        "window.text.color": colors.fg,
        "inactive.window.text.color": _rgba(colors.fg3, "b0"),
        "button.text.color": colors.fg,
        "disabled.text.color": colors.fg4,
        "tooltip.text.color": colors.fg,
        "highlight.text.color": colors.fg,
        "link.color": colors.blue,
        "link.visited.color": colors.purple,
        "progress.indicator.text.color": colors.fg,
    }.items():
        config.set("GeneralColors", key, value)

    for key, value in {
        "transparent_dolphin_view": "false",
        "transparent_ktitle_label": "true",
        "transparent_menutitle": "true",
    }.items():
        config.set("Hacks", key, value)

    for section, values in {
        "PanelButtonCommand": {
            "text.normal.color": colors.fg,
            "text.normal.inactive.color": _rgba(colors.fg2, "c8"),
            "text.focus.color": colors.fg,
            "text.press.color": colors.fg,
            "text.toggle.color": colors.fg,
            "text.toggle.inactive.color": _rgba(colors.fg2, "c8"),
        },
        "Dock": {
            "text.normal.color": colors.fg,
        },
        "DockTitle": {
            "text.normal.color": colors.fg,
            "text.focus.color": colors.fg,
        },
        "IndicatorSpinBox": {
            "text.normal.color": colors.fg,
        },
        "RadioButton": {
            "text.normal.color": colors.fg,
            "text.focus.color": colors.fg,
        },
        "CheckBox": {
            "text.normal.color": colors.fg,
            "text.focus.color": colors.fg,
        },
        "LineEdit": {
            "text.normal.color": colors.fg,
            "text.focus.color": colors.fg,
        },
        "ToolboxTab": {
            "text.normal.color": _rgba(colors.fg2, "d8"),
            "text.normal.inactive.color": _rgba(colors.fg3, "c8"),
            "text.press.color": colors.fg,
            "text.press.inactive.color": _rgba(colors.fg2, "c8"),
            "text.focus.color": colors.fg,
        },
        "Toolbar": {
            "text.normal.color": colors.fg,
            "text.focus.color": colors.fg,
        },
        "ItemView": {
            "text.normal.color": colors.fg,
            "text.normal.inactive.color": _rgba(colors.fg2, "c8"),
            "text.focus.color": colors.fg,
            "text.press.color": colors.fg,
            "text.toggle.color": colors.fg,
            "text.toggle.inactive.color": _rgba(colors.fg2, "eb"),
        },
        "Tab": {
            "text.normal.color": _rgba(colors.fg3, "c8"),
            "text.normal.inactive.color": _rgba(colors.fg4, "b0"),
            "text.focus.color": _rgba(colors.fg2, "e0"),
            "text.toggle.color": colors.fg,
        },
        "HeaderSection": {
            "text.normal.color": _rgba(colors.fg3, "c8"),
            "text.normal.inactive.color": _rgba(colors.fg4, "b0"),
            "text.focus.color": _rgba(colors.fg2, "e0"),
            "text.toggle.color": colors.fg,
        },
        "MenuItem": {
            "text.normal.color": colors.fg,
            "text.focus.color": colors.fg,
        },
        "MenuBarItem": {
            "text.normal.color": colors.fg,
            "text.focus.color": colors.fg,
        },
        "TitleBar": {
            "text.normal.color": _rgba(colors.fg3, "c8"),
            "text.focus.color": colors.fg,
        },
    }.items():
        if not config.has_section(section):
            config.add_section(section)
        for key, value in values.items():
            config.set(section, key, value)

    header = f"; Generated by apply-theme — {colors.family}-{colors.variant}\n\n"
    return _serialize_config(config, header=header)
