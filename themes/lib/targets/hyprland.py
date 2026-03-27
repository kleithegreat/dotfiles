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


def _rgba(hex_color: str, alpha: str = "ff") -> str:
    """Convert '#rrggbb' to Hyprland's rgba(rrggbbaa) format."""
    return f"rgba({hex_color[1:]}{alpha})"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    return (
        f"$theme_bg       = {_rgb(colors.bg)}\n"
        f"$theme_bg_rgba  = {_rgba(colors.bg)}\n"
        f"$theme_bg_dim   = {_rgb(colors.bg_dim)}\n"
        f"$theme_bg_dim_rgba = {_rgba(colors.bg_dim)}\n"
        f"$theme_bg1      = {_rgb(colors.bg1)}\n"
        f"$theme_bg1_rgba = {_rgba(colors.bg1)}\n"
        f"$theme_bg2      = {_rgb(colors.bg2)}\n"
        f"$theme_bg2_rgba = {_rgba(colors.bg2)}\n"
        f"$theme_bg3      = {_rgb(colors.bg3)}\n"
        f"$theme_bg3_rgba = {_rgba(colors.bg3)}\n"
        f"$theme_fg       = {_rgb(colors.fg)}\n"
        f"$theme_fg_rgba  = {_rgba(colors.fg)}\n"
        f"$theme_accent   = {_rgb(colors.accent)}\n"
        f"$theme_accent_rgba = {_rgba(colors.accent)}\n"
        f"$theme_red      = {_rgb(colors.red)}\n"
        f"$theme_red_rgba = {_rgba(colors.red)}\n"
        f"$theme_green    = {_rgb(colors.green)}\n"
        f"$theme_green_rgba = {_rgba(colors.green)}\n"
        f"$theme_yellow   = {_rgb(colors.yellow)}\n"
        f"$theme_yellow_rgba = {_rgba(colors.yellow)}\n"
        f"$theme_blue     = {_rgb(colors.blue)}\n"
        f"$theme_blue_rgba = {_rgba(colors.blue)}\n"
        f"$theme_purple   = {_rgb(colors.purple)}\n"
        f"$theme_purple_rgba = {_rgba(colors.purple)}\n"
        f"$theme_cyan     = {_rgb(colors.cyan)}\n"
        f"$theme_cyan_rgba = {_rgba(colors.cyan)}\n"
        f"$theme_orange   = {_rgb(colors.orange)}\n"
        f"$theme_orange_rgba = {_rgba(colors.orange)}\n"
        f"$theme_font     = {state.mono_font}\n"
        f"$theme_sys_font = {state.system_font}\n"
        f"$theme_font_size = {state.font_size}\n"
    )
