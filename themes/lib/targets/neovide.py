"""Neovide GUI font configuration (standalone Lua)."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "neovide"
ASSEMBLY = "standalone"
OUTPUT_PATH = "~/.config/nvim/lua/neovide-theme.lua"
RELOAD_CMD = None
COMMENT = "--"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    font = state.mono_font
    size = state.mono_font_size_for(TARGET_NAME)
    return f'vim.o.guifont = "{font}:h{size}"\n'
