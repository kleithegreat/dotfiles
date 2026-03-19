"""Wallpaper via swww (command)."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "wallpaper"
ASSEMBLY = "command"


def generate(colors: ColorScheme, state: ThemeState) -> list[list[str]]:
    return [
        ["swww", "img", state.wallpaper,
         "--transition-type", "fade",
         "--transition-duration", "1"],
    ]
