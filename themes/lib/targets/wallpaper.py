"""Wallpaper via swww, with optional lutgen filtering and output caching."""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
from pathlib import Path

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "wallpaper"
ASSEMBLY = "command"
_CACHE_VERSION = "lutgen-apply-v1"


def _swww_command(path: str) -> list[str]:
    return [
        "swww", "img", path,
        "--transition-type", "fade",
        "--transition-duration", "1",
    ]


def _cache_root() -> Path:
    base = os.environ.get("XDG_CACHE_HOME")
    if base:
        return Path(base).expanduser() / "apply-theme" / "wallpaper"
    return Path("~/.cache/apply-theme/wallpaper").expanduser()


def _cache_key(colors: ColorScheme, wallpaper: Path) -> str:
    stat = wallpaper.stat()
    digest = hashlib.sha256()
    digest.update(_CACHE_VERSION.encode())
    digest.update(str(wallpaper.resolve()).encode())
    digest.update(str(stat.st_size).encode())
    digest.update(str(stat.st_mtime_ns).encode())
    for color in colors.palette:
        digest.update(color.lower().encode())
    return digest.hexdigest()[:16]


def _filtered_wallpaper_path(colors: ColorScheme, state: ThemeState) -> Path:
    wallpaper = Path(state.wallpaper).expanduser()
    stem = "".join(ch if ch.isalnum() or ch in ("-", "_") else "-" for ch in wallpaper.stem)
    stem = stem.strip("-_") or "wallpaper"
    scheme = "".join(ch if ch.isalnum() or ch in ("-", "_") else "-" for ch in state.color_scheme)
    return _cache_root() / f"{stem}-{scheme}-{_cache_key(colors, wallpaper)}.png"


def _run_command(cmd: list[str]) -> tuple[bool, str]:
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        return True, ""
    except FileNotFoundError:
        return False, f"{cmd[0]!r} not found"
    except subprocess.CalledProcessError as exc:
        message = exc.stderr.strip() or exc.stdout.strip() or str(exc)
        return False, message


def generate(colors: ColorScheme, state: ThemeState) -> list[list[str]]:
    del colors
    if state.filter_wallpaper:
        return []
    return [_swww_command(state.wallpaper)]


def on_apply(colors: ColorScheme, state: ThemeState) -> None:
    if not state.filter_wallpaper:
        return

    source = Path(state.wallpaper).expanduser()

    try:
        filtered = _filtered_wallpaper_path(colors, state)
        if not filtered.is_file():
            filtered.parent.mkdir(parents=True, exist_ok=True)
            ok, message = _run_command(
                [
                    "lutgen",
                    "apply",
                    "--cache",
                    "-o",
                    str(filtered),
                    str(source),
                    "--",
                    *colors.palette,
                ]
            )
            if not ok:
                filtered.unlink(missing_ok=True)
                print(
                    f"  wallpaper warning: lutgen failed ({message}); falling back to original wallpaper",
                    file=sys.stderr,
                )
                filtered = source
        ok, message = _run_command(_swww_command(str(filtered)))
        if not ok:
            print(f"  wallpaper warning: {message}", file=sys.stderr)
    except Exception as exc:
        print(f"  wallpaper warning: {exc}", file=sys.stderr)
        ok, message = _run_command(_swww_command(str(source)))
        if not ok:
            print(f"  wallpaper warning: {message}", file=sys.stderr)
