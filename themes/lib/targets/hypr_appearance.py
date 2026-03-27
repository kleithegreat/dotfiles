"""Generated Hyprland appearance overrides."""

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "hypr_appearance"
ASSEMBLY = "standalone"
OUTPUT_PATH = "~/.config/hypr/appearance-theme.conf"
RELOAD_CMD = ["hyprctl", "reload"]
COMMENT = "#"


def _bool_word(value: bool) -> str:
    return "true" if value else "false"


def _yes_no(value: bool) -> str:
    return "yes" if value else "no"


def generate(colors: ColorScheme, state: ThemeState) -> str:
    del colors
    return (
        "general {\n"
        f"    gaps_in = {state.hypr_gaps_in}\n"
        f"    gaps_out = {state.hypr_gaps_out}\n"
        f"    border_size = {state.hypr_border_size}\n"
        "}\n"
        "\n"
        "decoration {\n"
        f"    rounding = {state.hypr_rounding}\n"
        "\n"
        "    blur {\n"
        f"        enabled = {_bool_word(state.hypr_blur_enabled)}\n"
        f"        size = {state.hypr_blur_size}\n"
        f"        passes = {state.hypr_blur_passes}\n"
        "    }\n"
        "}\n"
        "\n"
        "animations {\n"
        f"    enabled = {_yes_no(state.hypr_animations_enabled)}\n"
        "}\n"
    )
