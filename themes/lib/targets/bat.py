"""Bat syntax highlighter theme selector (standalone config)."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "bat"
ASSEMBLY = "standalone"
OUTPUT_PATH = "~/.config/bat/config"
RELOAD_CMD = None  # Bat reads config on each invocation

# Mapping from (family, variant) to bat's built-in theme name.
# Keys not present here fall back to "base16".
_BAT_THEMES: dict[tuple[str, str], str] = {
    ("gruvbox", "dark"): "gruvbox-dark",
    ("gruvbox", "light"): "gruvbox-light",
    ("solarized", "dark"): "Solarized (dark)",
    ("solarized", "light"): "Solarized (light)",
    ("catppuccin", "mocha"): "Catppuccin Mocha",
    ("catppuccin", "frappe"): "Catppuccin Frappe",
    ("catppuccin", "latte"): "Catppuccin Latte",
    ("catppuccin", "macchiato"): "Catppuccin Macchiato",
}

_FALLBACK = "base16"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    theme = _BAT_THEMES.get((colors.family, colors.variant), _FALLBACK)
    return f"--theme={theme}\n"
