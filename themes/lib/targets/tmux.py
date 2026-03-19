"""Tmux color theme generator."""

import os

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "tmux"
ASSEMBLY = "import"
OUTPUT_PATH = "~/.config/tmux/colors.conf"
RELOAD_CMD = ["tmux", "source-file", os.path.expanduser("~/.config/tmux/colors.conf")]
COMMENT = "#"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    return (
        f'set -g status-style "bg={colors.bg1},fg={colors.fg}"\n'
        f'set -g status-left "#[fg={colors.bg},bg={colors.accent},bold] #S #[bg={colors.bg1}] "\n'
        f'set -g status-right "#[fg={colors.fg}] %H:%M "\n'
        f'setw -g window-status-format " #I:#W "\n'
        f'setw -g window-status-current-format "#[fg={colors.bg},bg={colors.green},bold] #I:#W "\n'
        f'set -g pane-border-style "fg={colors.bg1}"\n'
        f'set -g pane-active-border-style "fg={colors.accent}"\n'
    )
