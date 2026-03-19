"""Neovim colorscheme state (standalone JSON)."""

import json

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "neovim"
ASSEMBLY = "standalone"
OUTPUT_PATH = "~/.config/nvim/lua/theme-state.json"
RELOAD_CMD = None  # Neovim reads on startup; autocmd can watch for changes


def generate(colors: ColorScheme, state: ThemeState) -> str:
    return json.dumps(
        {"colorscheme": colors.family, "background": colors.variant},
        indent=2,
    ) + "\n"
