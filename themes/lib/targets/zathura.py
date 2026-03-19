"""Zathura PDF viewer color theme generator."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "zathura"
ASSEMBLY = "import"
OUTPUT_PATH = "~/.config/zathura/colors"
RELOAD_CMD = None
COMMENT = "#"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    return (
        f'set default-bg "{colors.bg}"\n'
        f'set default-fg "{colors.fg}"\n'
        f'set statusbar-bg "{colors.bg1}"\n'
        f'set statusbar-fg "{colors.fg}"\n'
        f'set inputbar-bg "{colors.bg}"\n'
        f'set inputbar-fg "{colors.fg}"\n'
        f'set notification-bg "{colors.bg1}"\n'
        f'set notification-fg "{colors.fg}"\n'
        f'set notification-error-bg "{colors.red}"\n'
        f'set notification-error-fg "{colors.fg}"\n'
        f'set notification-warning-bg "{colors.yellow}"\n'
        f'set notification-warning-fg "{colors.bg}"\n'
        f'set highlight-color "{colors.yellow}"\n'
        f'set highlight-active-color "{colors.accent}"\n'
        f'set completion-bg "{colors.bg1}"\n'
        f'set completion-fg "{colors.fg}"\n'
        f'set completion-highlight-bg "{colors.accent}"\n'
        f'set completion-highlight-fg "{colors.bg}"\n'
        f'set recolor-lightcolor "{colors.bg}"\n'
        f'set recolor-darkcolor "{colors.fg}"\n'
        f'set recolor "true"\n'
        f'set recolor-keephue "false"\n'
    )
