"""Starship prompt palette generator."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "starship"
ASSEMBLY = "concat"
OUTPUT_PATH = "~/.config/starship.toml"
BASE_PATH = "~/repos/dotfiles/config/starship/base.toml"
RELOAD_CMD = None  # Starship re-reads config on next prompt render
COMMENT = "#"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    return (
        "\n[palettes.current]\n"
        f"color_fg0 = '{colors.fg}'\n"
        f"color_bg1 = '{colors.bg1}'\n"
        f"color_bg3 = '{colors.bg3}'\n"
        f"color_blue = '{colors.blue}'\n"
        f"color_aqua = '{colors.cyan}'\n"
        f"color_green = '{colors.green}'\n"
        f"color_orange = '{colors.orange}'\n"
        f"color_purple = '{colors.purple}'\n"
        f"color_red = '{colors.red}'\n"
        f"color_yellow = '{colors.yellow}'\n"
    )
