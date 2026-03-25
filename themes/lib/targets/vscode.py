"""VS Code settings theme generator."""

import json

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "vscode"
ASSEMBLY = "concat"
OUTPUT_PATH = "~/.config/Code/User/settings.json"
BASE_PATH = "~/repos/dotfiles/config/vscode/base.json"
RELOAD_CMD = None  # VS Code watches settings.json for changes

# Map (family, variant) to the installed extension's workbench.colorTheme string.
_THEME_MAP: dict[tuple[str, str], str] = {
    ("gruvbox", "dark"): "Gruvbox Dark Medium",
    ("gruvbox", "light"): "Gruvbox Light Medium",
    ("catppuccin", "mocha"): "Catppuccin Mocha",
    ("catppuccin", "latte"): "Catppuccin Latte",
    ("catppuccin", "frappe"): "Catppuccin Frappé",
    ("catppuccin", "macchiato"): "Catppuccin Macchiato",
    ("solarized", "dark"): "Solarized Dark+",
    ("solarized", "light"): "Solarized Light+",
    ("rose-pine", "dark"): "Rosé Pine",
    ("rose-pine", "light"): "Rosé Pine Dawn",
}


def _resolve_theme(family: str, variant: str) -> str:
    return _THEME_MAP.get((family, variant), f"{family}-{variant}")


def generate(colors: ColorScheme, state: ThemeState) -> str:
    return json.dumps({
        "workbench.colorTheme": _resolve_theme(colors.family, colors.variant),
        "editor.fontFamily": state.mono_font,
        "editor.fontSize": state.mono_font_size,
        "terminal.integrated.fontFamily": state.mono_font,
        "terminal.integrated.fontSize": state.mono_font_size,
    }, indent=2)
