"""GTK settings via dconf (command).

Uses dconf write instead of gsettings so it works in all contexts (gsettings
requires glib on PATH, which is only available during NixOS rebuilds).
"""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "gtk"
ASSEMBLY = "command"

_DCONF_PREFIX = "/org/gnome/desktop/interface/"


def _dconf_set(key: str, value: str) -> list[str]:
    return ["dconf", "write", f"{_DCONF_PREFIX}{key}", f"'{value}'"]


def generate(colors: ColorScheme, state: ThemeState) -> list[list[str]]:
    gtk_theme = "adw-gtk3-dark" if state.dark_hint else "adw-gtk3"
    color_pref = "prefer-dark" if state.dark_hint else "prefer-light"
    return [
        _dconf_set("gtk-theme", gtk_theme),
        _dconf_set("color-scheme", color_pref),
        _dconf_set("font-name", f"{state.system_font} {state.font_size}"),
        _dconf_set("monospace-font-name", f"{state.mono_font} {state.mono_font_size}"),
        _dconf_set("icon-theme", state.icon_theme),
    ]
