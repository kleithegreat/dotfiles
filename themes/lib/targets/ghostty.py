"""Ghostty terminal color theme generator."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "ghostty"
ASSEMBLY = "concat"
OUTPUT_PATH = "~/.config/ghostty/config"
BASE_PATH = "~/repos/dotfiles/config/ghostty/base"
RELOAD_CMD = None  # Ghostty watches config files and auto-reloads
COMMENT = "#"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    lines = [
        f"font-family = {state.mono_font}",
        f"font-size = {state.mono_font_size_for(TARGET_NAME)}",
        f"background = {colors.bg}",
        f"foreground = {colors.fg}",
        f"selection-background = {colors.bg3}",
        f"selection-foreground = {colors.fg}",
        f"cursor-color = {colors.fg}",
        f"cursor-text = {colors.bg}",
    ]
    for i, color in enumerate(colors.palette):
        lines.append(f"palette = {i}={color}")
    return "\n".join(lines) + "\n"
