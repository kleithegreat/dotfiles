"""Quickshell GeneratedTheme.json (standalone)."""

import json

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "quickshell"
ASSEMBLY = "standalone"
OUTPUT_PATH = "~/.config/quickshell/GeneratedTheme.json"
RELOAD_CMD = None  # Quickshell watches the file


def generate(colors: ColorScheme, state: ThemeState) -> str:
    theme = {
        "colors": {
            "bg": colors.bg,
            "bg0_h": colors.bg_dim,
            "bg1": colors.bg1,
            "bg2": colors.bg2,
            "bg3": colors.bg3,
            "fg": colors.fg,
            "fg2": colors.fg2,
            "fg3": colors.fg3,
            "fg4": colors.fg4,
            "red": colors.red,
            "green": colors.green,
            "yellow": colors.yellow,
            "blue": colors.blue,
            "purple": colors.purple,
            "aqua": colors.cyan,
            "orange": colors.orange,
            "redBright": colors.red_bright,
            "greenBright": colors.green_bright,
            "yellowBright": colors.yellow_bright,
            "blueBright": colors.blue_bright,
            "purpleBright": colors.purple_bright,
            "aquaBright": colors.cyan_bright,
            "orangeBright": colors.orange_bright,
            "accent": colors.accent,
        },
        "fonts": {
            "family": state.mono_font,
            "systemFamily": state.system_font,
            "size": 12,
            "sizeSmall": 10,
            "sizeLarge": 14,
        },
    }
    return json.dumps(theme, indent=2) + "\n"
