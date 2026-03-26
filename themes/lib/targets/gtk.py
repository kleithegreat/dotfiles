"""GTK settings files plus best-effort live GNOME settings updates."""

from __future__ import annotations

import subprocess

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "gtk"
ASSEMBLY = "standalone"
OUTPUT_PATH = "~/.config/gtk-3.0/settings.ini"
EXTRA_OUTPUTS = ["~/.config/gtk-4.0/settings.ini"]
COMMENT = "#"

_DCONF_PREFIX = "/org/gnome/desktop/interface/"


def _dconf_set(key: str, value: str) -> None:
    subprocess.run(
        ["dconf", "write", f"{_DCONF_PREFIX}{key}", value],
        check=True,
        capture_output=True,
        text=True,
    )


def generate(colors: ColorScheme, state: ThemeState) -> str:
    del colors
    gtk_theme = "adw-gtk3-dark" if state.dark_hint else "adw-gtk3"
    dark_hint = "1" if state.dark_hint else "0"
    return (
        "[Settings]\n"
        f"gtk-theme-name={gtk_theme}\n"
        f"gtk-icon-theme-name={state.icon_theme}\n"
        f"gtk-font-name={state.system_font} {state.font_size}\n"
        f"gtk-cursor-theme-name={state.cursor_theme}\n"
        f"gtk-cursor-theme-size={state.cursor_size}\n"
        f"gtk-application-prefer-dark-theme={dark_hint}\n"
    )


def on_apply(colors: ColorScheme, state: ThemeState) -> None:
    del colors
    gtk_theme = "adw-gtk3-dark" if state.dark_hint else "adw-gtk3"
    color_pref = "prefer-dark" if state.dark_hint else "prefer-light"
    _dconf_set("gtk-theme", f"'{gtk_theme}'")
    _dconf_set("color-scheme", f"'{color_pref}'")
    _dconf_set("font-name", f"'{state.system_font} {state.font_size}'")
    _dconf_set("monospace-font-name", f"'{state.mono_font} {state.mono_font_size}'")
    _dconf_set("icon-theme", f"'{state.icon_theme}'")
