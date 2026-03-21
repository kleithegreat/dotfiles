"""Qt6ct/qt5ct color scheme, KDE color globals, hyprqt6engine, and Kvantum generator."""

import configparser
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


def _argb(hex_color: str) -> str:
    """'#rrggbb' -> '#ffrrggbb' (full opacity)."""
    return f"#ff{hex_color[1:]}"


def _argb_alpha(hex_color: str, alpha: str = "80") -> str:
    """'#rrggbb' -> '#AArrggbb'."""
    return f"#{alpha}{hex_color[1:]}"


def _rgb(hex_color: str) -> str:
    """'#rrggbb' -> 'r,g,b' decimal for KDE config."""
    return f"{int(hex_color[1:3], 16)},{int(hex_color[3:5], 16)},{int(hex_color[5:7], 16)}"


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
        _argb(colors.bg),        # 10 Window
        _argb(colors.bg_dim),    # 11 Shadow
        _argb(colors.accent),    # 12 Highlight
        _argb(colors.fg),        # 13 HighlightedText
        _argb(colors.blue),      # 14 Link
        _argb(colors.purple),    # 15 LinkVisited
        _argb(colors.bg1),       # 16 AlternateBase
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


def on_apply(colors: ColorScheme, state: ThemeState) -> None:
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


def _update_qtct_config(conf_path: Path, scheme_path: str) -> None:
    """Set style, color_scheme_path, and custom_palette in a qt*ct.conf."""
    config = configparser.RawConfigParser()
    config.optionxform = str
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


def _apply_kde_colors(config: configparser.RawConfigParser,
                      colors: ColorScheme) -> None:
    """Write all KDE color sections to a configparser instance."""
    fg = _rgb(colors.fg)
    fg_dim = _rgb(colors.fg4)

    # Window: main window chrome (toolbars, sidebars, menubars)
    _kde_color_group(config, "Colors:Window",
                     _rgb(colors.bg), _rgb(colors.bg1), fg, fg_dim, colors)
    # View: content areas (file lists, text edits, tree views)
    _kde_color_group(config, "Colors:View",
                     _rgb(colors.bg), _rgb(colors.bg1), fg, fg_dim, colors)
    # Button: buttons and button-like controls
    _kde_color_group(config, "Colors:Button",
                     _rgb(colors.bg1), _rgb(colors.bg2), fg, fg_dim, colors)
    # Selection: highlighted/selected items
    _kde_color_group(config, "Colors:Selection",
                     _rgb(colors.accent), _rgb(colors.accent),
                     fg, _rgb(colors.fg2), colors)
    # Tooltip: popup tooltips
    _kde_color_group(config, "Colors:Tooltip",
                     _rgb(colors.bg1), _rgb(colors.bg), fg, fg_dim, colors)
    # Complementary: header bars, panel backgrounds
    _kde_color_group(config, "Colors:Complementary",
                     _rgb(colors.bg_dim), _rgb(colors.bg), fg, fg_dim, colors)
    # Header: column headers, title bars
    _kde_color_group(config, "Colors:Header",
                     _rgb(colors.bg1), _rgb(colors.bg_dim), fg, fg_dim, colors)

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
    config.set("WM", "activeBackground", _rgb(colors.bg_dim))
    config.set("WM", "activeForeground", fg)
    config.set("WM", "inactiveBackground", _rgb(colors.bg_dim))
    config.set("WM", "inactiveForeground", fg_dim)

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
    config = configparser.RawConfigParser()
    config.optionxform = str
    if conf_path.is_file():
        config.read(str(conf_path))
    _apply_kde_colors(config, colors)
    with open(conf_path, "w") as f:
        config.write(f, space_around_delimiters=False)


def _write_kcolorscheme(colors: ColorScheme) -> None:
    """Write a standalone KColorScheme .colors file for hyprqt6engine."""
    conf_path = Path(_KCOLORSCHEME).expanduser()
    conf_path.parent.mkdir(parents=True, exist_ok=True)
    config = configparser.RawConfigParser()
    config.optionxform = str
    _apply_kde_colors(config, colors)
    with open(conf_path, "w") as f:
        config.write(f, space_around_delimiters=False)


def _write_hyprqt6engine_conf(colors: ColorScheme, state: ThemeState) -> None:
    """Write hyprqt6engine.conf (hyprlang format) pointing to the qt6ct palette."""
    conf_path = Path(_HYPRQT6ENGINE_CONF).expanduser()
    scheme_path = str(Path(OUTPUT_PATH).expanduser())
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
            f"    font_fixed_size = {state.mono_font_size}\n"
            f"}}\n"
            f"\n"
            f"misc {{\n"
            f"    menus_have_icons = true\n"
            f"    single_click_activate = false\n"
            f"    shortcuts_for_context_menus = true\n"
            f"}}\n"
        )


def _find_kvantum_svg(theme_name: str) -> Path | None:
    """Search standard paths for a Kvantum theme SVG."""
    svg_name = f"{theme_name}.svg"
    # XDG_DATA_DIRS covers Nix profiles and system paths
    for data_dir in os.environ.get("XDG_DATA_DIRS", "").split(":"):
        if not data_dir:
            continue
        svg = Path(data_dir) / "Kvantum" / theme_name / svg_name
        if svg.is_file():
            return svg
    # Fallback: user Nix profile and system profile
    for prefix in [
        Path.home() / ".nix-profile" / "share",
        Path("/run/current-system/sw/share"),
    ]:
        svg = prefix / "Kvantum" / theme_name / svg_name
        if svg.is_file():
            return svg
    return None


def _setup_kvantum(colors: ColorScheme) -> None:
    """Generate and install a custom Kvantum theme with colors from the scheme."""
    theme_dir = Path(_KVANTUM_THEME_DIR).expanduser()
    theme_dir.mkdir(parents=True, exist_ok=True)

    # Write kvconfig with our mapped colors
    kvconfig_path = theme_dir / f"{_KVANTUM_THEME_NAME}.kvconfig"
    kvconfig_path.write_text(_generate_kvantum_kvconfig(colors))

    # Symlink SVG from the best matching installed Kvantum base theme
    svg_link = theme_dir / f"{_KVANTUM_THEME_NAME}.svg"
    base_theme = "KvGnomeDark" if colors.variant == "dark" else "KvGnome"
    source_svg = _find_kvantum_svg(base_theme)
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


def _generate_kvantum_kvconfig(colors: ColorScheme) -> str:
    """Generate a Kvantum .kvconfig with colors mapped from the current scheme."""
    return (
        f"; Generated by apply-theme — {colors.family}-{colors.variant}\n"
        "\n"
        "[%General]\n"
        "animate_states=true\n"
        "attach_active_tab=false\n"
        "blurring=false\n"
        "bold_font_weight=Bold\n"
        "button_contents_shift=false\n"
        "center_toolbar_handle=true\n"
        "combo_as_lineedit=true\n"
        "combo_focus_rect=false\n"
        "combo_menu=true\n"
        "composite=true\n"
        "fill_rubberband=false\n"
        "group_toolbar_buttons=false\n"
        "groupbox_top_label=true\n"
        "inline_spin_indicators=false\n"
        "interior_x11drag=true\n"
        "joined_inactive_tabs=false\n"
        "large_icon_size=32\n"
        "layout_margin=4\n"
        "layout_spacing=2\n"
        "left_tabs=false\n"
        "menu_shadow_depth=5\n"
        "menubar_mouse_tracking=true\n"
        "merge_menubar_with_toolbar=false\n"
        "mirror_doc_tabs=true\n"
        "no_inactiveness=false\n"
        "popup_blurring=false\n"
        "reduce_menu_opacity=0\n"
        "reduce_window_opacity=0\n"
        "respect_DE=true\n"
        "scroll_arrows=true\n"
        "scroll_min_extent=36\n"
        "scroll_width=12\n"
        "scrollable_menu=false\n"
        "scrollbar_in_view=false\n"
        "slider_handle_length=22\n"
        "slider_handle_width=22\n"
        "slider_width=2\n"
        "small_icon_size=16\n"
        "spin_button_width=16\n"
        "splitter_width=7\n"
        "spread_header=true\n"
        "spread_menuitems=true\n"
        "spread_progressbar=true\n"
        "submenu_delay=250\n"
        "submenu_overlap=0\n"
        "textless_progressbar=false\n"
        "tickless_slider_handle_size=22\n"
        "toolbar_icon_size=22\n"
        "toolbar_interior_spacing=2\n"
        "toolbar_item_spacing=0\n"
        "toolbutton_style=0\n"
        "tooltip_shadow_depth=6\n"
        "transient_groove=true\n"
        "transient_scrollbar=true\n"
        "tree_branch_line=true\n"
        "vertical_spin_indicators=false\n"
        "x11drag=all\n"
        "\n"
        "[GeneralColors]\n"
        f"window.color={colors.bg}\n"
        f"base.color={colors.bg}\n"
        f"alt.base.color={colors.bg}\n"
        f"button.color={colors.bg1}\n"
        f"light.color={colors.bg3}\n"
        f"mid.light.color={colors.bg2}\n"
        f"dark.color={colors.bg_dim}\n"
        f"mid.color={colors.bg1}\n"
        f"highlight.color={colors.accent}\n"
        f"inactive.highlight.color={colors.bg2}\n"
        f"tooltip.base.color={colors.bg1}\n"
        f"text.color={colors.fg}\n"
        f"window.text.color={colors.fg}\n"
        f"button.text.color={colors.fg}\n"
        f"disabled.text.color={colors.fg4}\n"
        f"tooltip.text.color={colors.fg}\n"
        f"highlight.text.color={colors.fg}\n"
        f"link.color={colors.blue}\n"
        f"link.visited.color={colors.purple}\n"
        f"progress.indicator.text.color={colors.fg}\n"
        "\n"
        "[Hacks]\n"
        "kcapacitybar_as_progressbar=true\n"
        "kinetic_scrolling=false\n"
        "middle_click_scroll=false\n"
        "normal_default_pushbutton=true\n"
        "opaque_colors=false\n"
        "respect_darkness=false\n"
        "scroll_jump_workaround=true\n"
        "tint_on_mouseover=0\n"
        "transparent_arrow_button=true\n"
        "transparent_dolphin_view=false\n"
        "transparent_ktitle_label=true\n"
        "transparent_menutitle=true\n"
    )
