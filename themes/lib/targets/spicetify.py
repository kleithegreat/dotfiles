"""Spicetify color scheme generator."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "spicetify"
ASSEMBLY = "standalone"
_THEME_NAME = "ApplyTheme"
_SCHEME_NAME = "Base"
OUTPUT_PATH = f"~/.config/spicetify/Themes/{_THEME_NAME}/color.ini"
RELOAD_CMD = None
COMMENT = ";"

_THEME_DIR = Path(f"~/.config/spicetify/Themes/{_THEME_NAME}").expanduser()
_USER_CSS_PATH = _THEME_DIR / "user.css"


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


def _is_light_scheme(colors: ColorScheme) -> bool:
    return _relative_luminance(colors.bg) > _relative_luminance(colors.fg)


def _blend(first: str, second: str, factor: float) -> str:
    factor = max(0.0, min(factor, 1.0))
    channels: list[int] = []
    for offset in (1, 3, 5):
        start = int(first[offset:offset + 2], 16)
        end = int(second[offset:offset + 2], 16)
        channels.append(round(start + (end - start) * factor))
    return f"#{channels[0]:02x}{channels[1]:02x}{channels[2]:02x}"


def _spice_hex(hex_color: str) -> str:
    return hex_color[1:]


def _shadow(colors: ColorScheme) -> str:
    if _is_light_scheme(colors):
        return colors.bg3
    return colors.bg_dim


def _button_active(colors: ColorScheme) -> str:
    return _blend(colors.accent, colors.fg, 0.18)


def _button_disabled(colors: ColorScheme) -> str:
    if _is_light_scheme(colors):
        return colors.fg4
    return colors.bg3


def generate(colors: ColorScheme, state: ThemeState) -> str:
    del state

    # Spicetify exposes a small set of CSS-oriented surfaces. Keep the shell
    # close to the primary background and reserve brighter/darker surfaces for
    # cards, tabs, and stateful controls.
    mapping = {
        "text": colors.fg,
        "subtext": colors.fg3,
        "main": colors.bg,
        "sidebar": colors.bg_dim,
        "player": colors.bg,
        "card": colors.bg1,
        "shadow": _shadow(colors),
        "selected-row": colors.fg2,
        "button": colors.accent,
        "button-active": _button_active(colors),
        "button-disabled": _button_disabled(colors),
        "tab-active": colors.bg2,
        "notification": colors.blue,
        "notification-error": colors.red,
        "misc": colors.fg4,
    }
    lines = [f"[{_SCHEME_NAME}]"]
    lines.extend(f"{key} = {_spice_hex(value)}" for key, value in mapping.items())
    return "\n".join(lines) + "\n"


def persist(colors: ColorScheme, state: ThemeState) -> None:
    del colors, state
    if _USER_CSS_PATH.exists():
        return
    _USER_CSS_PATH.parent.mkdir(parents=True, exist_ok=True)
    _USER_CSS_PATH.write_text(
        "/* Optional Spicetify CSS overrides managed outside apply-theme. */\n"
    )


def on_apply(colors: ColorScheme, state: ThemeState) -> None:
    del colors, state
    if shutil.which("spicetify") is None:
        return
    subprocess.run(
        ["spicetify", "update"],
        check=True,
        capture_output=True,
        text=True,
    )
