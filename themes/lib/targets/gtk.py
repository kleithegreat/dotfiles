"""GTK settings via gsettings (command)."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "gtk"
ASSEMBLY = "command"


def generate(colors: ColorScheme, state: ThemeState) -> list[list[str]]:
    gtk_theme = "adw-gtk3-dark" if state.dark_hint else "adw-gtk3"
    color_pref = "prefer-dark" if state.dark_hint else "prefer-light"
    return [
        ["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", gtk_theme],
        ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", color_pref],
        ["gsettings", "set", "org.gnome.desktop.interface", "font-name", f"{state.system_font} {state.font_size}"],
        ["gsettings", "set", "org.gnome.desktop.interface", "monospace-font-name", f"{state.mono_font} {state.mono_font_size}"],
        ["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", state.icon_theme],
    ]
