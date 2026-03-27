"""Core dataclasses for the theming system."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import ClassVar


@dataclass(frozen=True)
class ColorScheme:
    """All color values are 7-character hex strings: '#rrggbb'."""

    family: str           # e.g. "gruvbox", "solarized", "catppuccin"
    variant: str          # "dark" or "light"

    # Backgrounds (darkest → lightest for dark themes, reversed for light)
    bg: str               # Primary background
    bg_dim: str           # Dimmer background (darker than bg for dark themes)
    bg1: str              # Surface / elevated background
    bg2: str              # Surface variant
    bg3: str              # Borders, subtle separators

    # Foregrounds (brightest → dimmest)
    fg: str               # Primary text
    fg2: str              # Secondary text
    fg3: str              # Tertiary / muted text
    fg4: str              # Placeholder / disabled text

    # Semantic colors
    red: str
    green: str
    yellow: str
    blue: str
    purple: str
    cyan: str
    orange: str

    # Accent (used for focused borders, selections, active indicators)
    accent: str

    # Bright variants (for terminal bold, highlights)
    red_bright: str
    green_bright: str
    yellow_bright: str
    blue_bright: str
    purple_bright: str
    cyan_bright: str
    orange_bright: str

    # 16-color terminal palette (indices 0-15)
    # Standard order: black, red, green, yellow, blue, magenta, cyan, white,
    #                 bright_black, bright_red, ..., bright_white
    palette: tuple[str, ...]  # Exactly 16 entries

    @classmethod
    def from_json(cls, path: Path) -> ColorScheme:
        """Load a ColorScheme from a color JSON file."""
        data = json.loads(path.read_text())
        colors = data["colors"]
        return cls(
            family=data["family"],
            variant=data["variant"],
            palette=tuple(data["palette"]),
            **colors,
        )


@dataclass(frozen=True)
class ThemeState:
    MONO_FONT_SIZE_OFFSET_KEYS: ClassVar[dict[str, str]] = {
        "alacritty": "alacritty_mono_font_size_offset",
        "ghostty": "ghostty_mono_font_size_offset",
        "gtk": "gtk_mono_font_size_offset",
        "qt": "qt_mono_font_size_offset",
        "vscode": "vscode_mono_font_size_offset",
    }

    color_scheme: str      # Key into themes/colors/ (e.g. "gruvbox-dark")
    wallpaper: str         # Absolute path (e.g. "/home/kevin/wallpapers/lmao.png")
    filter_wallpaper: bool # True = color-grade wallpaper to match active palette
    system_font: str       # e.g. "Overpass"
    mono_font: str         # e.g. "JetBrains Mono Nerd Font"
    icon_theme: str        # e.g. "Papirus-Dark"
    cursor_theme: str      # e.g. "Adwaita"
    cursor_size: int       # e.g. 24
    font_size: int         # System font size (e.g. 11)
    mono_font_size: int    # Terminal/editor font size (e.g. 11)
    alacritty_mono_font_size_offset: int  # Per-target delta from mono_font_size
    ghostty_mono_font_size_offset: int
    gtk_mono_font_size_offset: int
    qt_mono_font_size_offset: int
    vscode_mono_font_size_offset: int
    dark_hint: bool        # True = prefer-dark, False = prefer-light
    hypr_gaps_in: int
    hypr_gaps_out: int
    hypr_border_size: int
    hypr_rounding: int
    hypr_blur_enabled: bool
    hypr_blur_size: int
    hypr_blur_passes: int
    hypr_animations_enabled: bool

    def mono_font_size_offset_for(self, target_name: str) -> int:
        """Return the mono font size offset configured for a target."""
        try:
            offset_key = self.MONO_FONT_SIZE_OFFSET_KEYS[target_name]
        except KeyError as exc:
            raise ValueError(f"Unknown mono font size target: {target_name}") from exc
        return getattr(self, offset_key)

    def mono_font_size_for(self, target_name: str) -> int:
        """Return the base mono font size plus the target-specific offset."""
        return self.mono_font_size + self.mono_font_size_offset_for(target_name)

    @classmethod
    def from_json(cls, path: Path) -> ThemeState:
        """Load ThemeState from state.json."""
        data = json.loads(path.read_text())
        return cls(**data)
