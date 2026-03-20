"""Qt6ct/qt5ct color scheme and KDE color globals generator."""

import configparser
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
    """Update qt6ct/qt5ct configs and KDE globals."""
    for conf, scheme in [
        (_QT6CT_CONF, OUTPUT_PATH),
        (_QT5CT_CONF, EXTRA_OUTPUTS[0]),
    ]:
        _update_qtct_config(
            Path(conf).expanduser(),
            str(Path(scheme).expanduser()),
        )
    _update_kdeglobals(colors)


def _update_qtct_config(conf_path: Path, scheme_path: str) -> None:
    """Set style, color_scheme_path, and custom_palette in a qt*ct.conf."""
    config = configparser.RawConfigParser()
    config.optionxform = str
    if conf_path.is_file():
        config.read(str(conf_path))
    if not config.has_section("Appearance"):
        config.add_section("Appearance")
    config.set("Appearance", "style", "Fusion")
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


def _update_kdeglobals(colors: ColorScheme) -> None:
    """Write KDE color groups to ~/.config/kdeglobals."""
    conf_path = Path(_KDEGLOBALS).expanduser()
    config = configparser.RawConfigParser()
    config.optionxform = str
    if conf_path.is_file():
        config.read(str(conf_path))

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

    with open(conf_path, "w") as f:
        config.write(f, space_around_delimiters=False)
