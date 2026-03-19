"""Cursor theme via gsettings + hyprctl (command)."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "cursor"
ASSEMBLY = "command"


def generate(colors: ColorScheme, state: ThemeState) -> list[list[str]]:
    return [
        ["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", state.cursor_theme],
        ["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", str(state.cursor_size)],
        ["hyprctl", "setcursor", state.cursor_theme, str(state.cursor_size)],
    ]
