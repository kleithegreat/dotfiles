"""Load and validate color schemes and theme state."""

from __future__ import annotations

import json
import re
import typing
from dataclasses import asdict, fields
from pathlib import Path

from .schema import ColorScheme, ThemeState

_HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

# ColorScheme fields that hold hex color values (everything except metadata).
_COLOR_FIELDS = frozenset(
    f.name for f in fields(ColorScheme) if f.name not in ("family", "variant", "palette")
)

_STATE_HINTS = typing.get_type_hints(ThemeState)
_STATE_STR_FIELDS = frozenset(name for name, tp in _STATE_HINTS.items() if tp is str)
_STATE_INT_FIELDS = frozenset(name for name, tp in _STATE_HINTS.items() if tp is int)


def _check_hex(value: str, label: str) -> None:
    if not _HEX_RE.match(value):
        raise ValueError(f"{label}: expected '#rrggbb' hex color, got {value!r}")


def load_colors(scheme_name: str, colors_dir: Path) -> ColorScheme:
    """Read ``colors/<scheme_name>.json`` and return a validated ColorScheme."""
    path = colors_dir / f"{scheme_name}.json"
    if not path.is_file():
        available = sorted(p.stem for p in colors_dir.glob("*.json"))
        raise FileNotFoundError(
            f"Color scheme '{scheme_name}' not found at {path}. "
            f"Available: {', '.join(available) or '(none)'}"
        )

    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {path}: {exc}") from exc

    # --- top-level keys ---
    for key in ("family", "variant", "colors", "palette"):
        if key not in data:
            raise ValueError(f"{path}: missing required top-level key '{key}'")

    # --- colors object ---
    colors = data["colors"]
    missing = _COLOR_FIELDS - colors.keys()
    if missing:
        raise ValueError(f"{path}: missing color keys: {', '.join(sorted(missing))}")

    for name in sorted(_COLOR_FIELDS):
        _check_hex(colors[name], f"{path} colors.{name}")

    # --- palette ---
    palette = data["palette"]
    if not isinstance(palette, list) or len(palette) != 16:
        raise ValueError(f"{path}: 'palette' must be a list of exactly 16 hex colors")

    for i, entry in enumerate(palette):
        _check_hex(entry, f"{path} palette[{i}]")

    return ColorScheme(
        family=data["family"],
        variant=data["variant"],
        palette=tuple(palette),
        **colors,
    )


def load_state(state_path: Path) -> ThemeState:
    """Read ``state.json`` and return a validated ThemeState."""
    if not state_path.is_file():
        raise FileNotFoundError(f"Theme state file not found: {state_path}")

    try:
        data = json.loads(state_path.read_text())
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {state_path}: {exc}") from exc

    expected = {f.name for f in fields(ThemeState)}
    missing = expected - data.keys()
    if missing:
        raise ValueError(
            f"{state_path}: missing required keys: {', '.join(sorted(missing))}"
        )

    for name in sorted(_STATE_STR_FIELDS):
        if not isinstance(data[name], str) or not data[name]:
            raise ValueError(f"{state_path}: '{name}' must be a non-empty string")

    for name in sorted(_STATE_INT_FIELDS):
        if not isinstance(data[name], int) or isinstance(data[name], bool):
            raise ValueError(f"{state_path}: '{name}' must be an integer")

    return ThemeState(**data)


def save_state(state: ThemeState, state_path: Path) -> None:
    """Write a ThemeState to ``state.json`` with stable formatting."""
    state_path.write_text(json.dumps(asdict(state), indent=2) + "\n")
