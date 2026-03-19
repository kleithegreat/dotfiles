"""Hyprland color variables (standalone)."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "hyprland"
ASSEMBLY = "standalone"
OUTPUT_PATH = "~/.config/hypr/colors.conf"
RELOAD_CMD = ["hyprctl", "reload"]
COMMENT = "#"


def _rgb(hex_color: str) -> str:
    """Convert '#rrggbb' to Hyprland's rgb(rrggbb) format."""
    return f"rgb({hex_color[1:]})"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    return (
        f"$theme_bg       = {_rgb(colors.bg)}\n"
        f"$theme_bg_dim   = {_rgb(colors.bg_dim)}\n"
        f"$theme_bg1      = {_rgb(colors.bg1)}\n"
        f"$theme_bg2      = {_rgb(colors.bg2)}\n"
        f"$theme_bg3      = {_rgb(colors.bg3)}\n"
        f"$theme_fg       = {_rgb(colors.fg)}\n"
        f"$theme_accent   = {_rgb(colors.accent)}\n"
        f"$theme_red      = {_rgb(colors.red)}\n"
        f"$theme_green    = {_rgb(colors.green)}\n"
        f"$theme_yellow   = {_rgb(colors.yellow)}\n"
        f"$theme_blue     = {_rgb(colors.blue)}\n"
        f"$theme_purple   = {_rgb(colors.purple)}\n"
        f"$theme_cyan     = {_rgb(colors.cyan)}\n"
        f"$theme_orange   = {_rgb(colors.orange)}\n"
        f"$theme_font     = {state.mono_font}\n"
        f"$theme_sys_font = {state.system_font}\n"
        f"$theme_font_size = {state.font_size}\n"
    )
