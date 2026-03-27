"""GTK live settings updates without owning GTK settings files."""

from __future__ import annotations

import subprocess

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "gtk"
ASSEMBLY = "command"
# GTK theming is live-session state only; there is nothing to persist during
# Home Manager's non-interactive sync pass.
SYNC_SAFE = False

_DCONF_PREFIX = "/org/gnome/desktop/interface/"


def _dconf_set(key: str, value: str) -> None:
    subprocess.run(
        ["dconf", "write", f"{_DCONF_PREFIX}{key}", value],
        check=True,
        capture_output=True,
        text=True,
    )


def generate(colors: ColorScheme, state: ThemeState) -> list[list[str]]:
    del colors, state
    return []


def on_apply(colors: ColorScheme, state: ThemeState) -> None:
    del colors
    gtk_theme = "adw-gtk3-dark" if state.dark_hint else "adw-gtk3"
    color_pref = "prefer-dark" if state.dark_hint else "prefer-light"
    _dconf_set("gtk-theme", f"'{gtk_theme}'")
    _dconf_set("color-scheme", f"'{color_pref}'")
    _dconf_set("font-name", f"'{state.system_font} {state.font_size}'")
    _dconf_set(
        "monospace-font-name",
        f"'{state.mono_font} {state.mono_font_size_for(TARGET_NAME)}'",
    )
    _dconf_set("icon-theme", f"'{state.icon_theme}'")
