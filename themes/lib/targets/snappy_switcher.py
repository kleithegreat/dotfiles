"""Snappy Switcher theme generator."""

from __future__ import annotations

import os
import shutil
import subprocess

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "snappy_switcher"
ASSEMBLY = "concat"
OUTPUT_PATH = "~/.config/snappy-switcher/config.ini"
BASE_PATH = "~/repos/dotfiles/config/snappy-switcher/base.ini"
RELOAD_CMD = None
COMMENT = "#"

_THEME_FILE_MAP = {
    "catppuccin-frappe": "catppuccin-mocha.ini",
    "catppuccin-latte": "catppuccin-latte.ini",
    "catppuccin-macchiato": "catppuccin-mocha.ini",
    "catppuccin-mocha": "catppuccin-mocha.ini",
    "gruvbox-dark": "gruvbox-dark.ini",
    "nord": "nord.ini",
    "nord-light": "catppuccin-latte.ini",
    "rose-pine": "rose-pine.ini",
    "rose-pine-dawn": "catppuccin-latte.ini",
    "solarized-dark": "snappy-slate.ini",
    "solarized-light": "catppuccin-latte.ini",
    "tokyo-night": "tokyo-night.ini",
    "tokyo-night-light": "catppuccin-latte.ini",
}


def _rgba(hex_color: str, alpha: str = "ff") -> str:
    """'#rrggbb' -> '#rrggbbaa'."""
    return f"{hex_color}{alpha}"


def _theme_name(state: ThemeState, colors: ColorScheme) -> str:
    """Pick a bundled theme filename as the base theme."""
    theme = _THEME_FILE_MAP.get(state.color_scheme)
    if theme is not None:
        return theme
    if colors.variant == "light":
        return "catppuccin-latte.ini"
    return "snappy-slate.ini"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    title_size = max(state.font_size - 1, 1)
    return f"""\
[theme]
name = {_theme_name(state, colors)}
background = {_rgba(colors.bg)}
card_bg = {_rgba(colors.bg1)}
card_selected = {_rgba(colors.bg2)}
text_color = {_rgba(colors.fg)}
subtext_color = {_rgba(colors.fg4)}
border_color = {_rgba(colors.accent)}
bundle_bg = {_rgba(colors.bg1, "cc")}
badge_bg = {_rgba(colors.accent)}
badge_text_color = {_rgba(colors.bg)}
workspace_color = {_rgba(colors.fg)}
border_width = 2
corner_radius = 12

[icons]
theme = {state.icon_theme}
fallback = Adwaita

[font]
family = {state.system_font}
weight = Bold
title_size = {title_size}
"""


def on_apply(colors: ColorScheme, state: ThemeState) -> None:
    """Restart the daemon so it picks up config changes."""
    del colors, state

    if not os.environ.get("WAYLAND_DISPLAY"):
        return

    snappy = shutil.which("snappy-switcher")
    if snappy is None:
        return

    with open(os.devnull, "w") as devnull:
        subprocess.run(
            [snappy, "quit"],
            check=False,
            stdout=devnull,
            stderr=devnull,
        )
        subprocess.Popen(
            [snappy, "--daemon"],
            stdout=devnull,
            stderr=devnull,
            start_new_session=True,
        )
