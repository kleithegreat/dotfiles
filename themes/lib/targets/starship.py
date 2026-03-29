"""Starship prompt palette generator."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "starship"
ASSEMBLY = "concat"
OUTPUT_PATH = "~/.config/starship.toml"
BASE_PATH = "~/repos/dotfiles/config/starship/base.toml"
RELOAD_CMD = None  # Starship re-reads config on next prompt render
COMMENT = "#"
WCAG_AA_NORMAL_TEXT = 4.5


def _srgb_channel_to_linear(channel: int) -> float:
    value = channel / 255
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def _relative_luminance(hex_color: str) -> float:
    red = _srgb_channel_to_linear(int(hex_color[1:3], 16))
    green = _srgb_channel_to_linear(int(hex_color[3:5], 16))
    blue = _srgb_channel_to_linear(int(hex_color[5:7], 16))
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def _contrast_ratio(first: str, second: str) -> float:
    lighter, darker = sorted(
        (_relative_luminance(first), _relative_luminance(second)),
        reverse=True,
    )
    return (lighter + 0.05) / (darker + 0.05)


def _accent_foreground(accent: str, colors: ColorScheme) -> str:
    """Pick readable text for accent segments without disturbing good schemes."""
    candidates = [
        colors.fg, colors.bg,
        colors.fg2, colors.fg3, colors.fg4,
        colors.bg_dim, colors.bg1, colors.bg2, colors.bg3,
    ]
    for candidate in candidates:
        if _contrast_ratio(accent, candidate) >= WCAG_AA_NORMAL_TEXT:
            return candidate

    black = "#000000"
    white = "#ffffff"
    if _contrast_ratio(accent, black) >= _contrast_ratio(accent, white):
        return black
    return white


def generate(colors: ColorScheme, state: ThemeState) -> str:
    return (
        "\n[palettes.current]\n"
        f"color_fg0 = '{colors.fg}'\n"
        f"color_bg1 = '{colors.bg1}'\n"
        f"color_bg3 = '{colors.bg3}'\n"
        f"color_blue = '{colors.blue}'\n"
        f"color_blue_fg = '{_accent_foreground(colors.blue, colors)}'\n"
        f"color_aqua = '{colors.cyan}'\n"
        f"color_aqua_fg = '{_accent_foreground(colors.cyan, colors)}'\n"
        f"color_green = '{colors.green}'\n"
        f"color_orange = '{colors.orange}'\n"
        f"color_orange_fg = '{_accent_foreground(colors.orange, colors)}'\n"
        f"color_purple = '{colors.purple}'\n"
        f"color_red = '{colors.red}'\n"
        f"color_yellow = '{colors.yellow}'\n"
        f"color_yellow_fg = '{_accent_foreground(colors.yellow, colors)}'\n"
    )
