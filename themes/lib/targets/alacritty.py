"""Alacritty terminal color theme generator."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "alacritty"
ASSEMBLY = "import"
OUTPUT_PATH = "~/.config/alacritty/theme.toml"
RELOAD_CMD = None  # Alacritty watches config files and auto-reloads
COMMENT = "#"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    return f"""\
[font]
normal = {{ family = "{state.mono_font}" }}
size = {state.mono_font_size}

[colors.primary]
background = "{colors.bg}"
foreground = "{colors.fg}"

[colors.normal]
black   = "{colors.palette[0]}"
red     = "{colors.palette[1]}"
green   = "{colors.palette[2]}"
yellow  = "{colors.palette[3]}"
blue    = "{colors.palette[4]}"
magenta = "{colors.palette[5]}"
cyan    = "{colors.palette[6]}"
white   = "{colors.palette[7]}"

[colors.bright]
black   = "{colors.palette[8]}"
red     = "{colors.palette[9]}"
green   = "{colors.palette[10]}"
yellow  = "{colors.palette[11]}"
blue    = "{colors.palette[12]}"
magenta = "{colors.palette[13]}"
cyan    = "{colors.palette[14]}"
white   = "{colors.palette[15]}"
"""
