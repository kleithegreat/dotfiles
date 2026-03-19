"""Vicinae application launcher theme generator."""

import json

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "vicinae"
ASSEMBLY = "concat"
OUTPUT_PATH = "~/.config/vicinae/settings.json"
BASE_PATH = "~/repos/dotfiles/config/vicinae/base.json"
RELOAD_CMD = None  # Vicinae auto-reloads

# Map (family, variant) to vicinae's built-in theme name.
# Falls back to "family-variant" for unknown combinations.
_THEME_MAP: dict[tuple[str, str], str] = {
    ("gruvbox", "dark"): "gruvbox-dark",
    ("gruvbox", "light"): "gruvbox-light",
    ("solarized", "dark"): "solarized-dark",
    ("solarized", "light"): "solarized-light",
    ("catppuccin", "mocha"): "catppuccin-mocha",
    ("catppuccin", "latte"): "catppuccin-latte",
    ("catppuccin", "frappe"): "catppuccin-frappe",
    ("catppuccin", "macchiato"): "catppuccin-macchiato",
    ("nord", "dark"): "nord",
    ("dracula", "dark"): "dracula",
    ("rose-pine", "dark"): "rose-pine",
    ("rose-pine", "light"): "rose-pine-dawn",
    ("tokyo-night", "dark"): "tokyo-night",
}


def _resolve_theme(family: str, variant: str) -> str:
    return _THEME_MAP.get((family, variant), f"{family}-{variant}")


def generate(colors: ColorScheme, state: ThemeState) -> str:
    theme_name = _resolve_theme(colors.family, colors.variant)
    return json.dumps({
        "font": {"normal": {"family": state.system_font}},
        "theme": {
            "dark": {"name": theme_name},
            "light": {"name": _resolve_theme(colors.family, "light")},
        },
    }, indent=2)
