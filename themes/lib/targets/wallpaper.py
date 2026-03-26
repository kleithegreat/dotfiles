"""Wallpaper via swww, with optional lutgen filtering and output caching."""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

from themes.lib.schema import ColorScheme, ThemeState

TARGET_NAME = "wallpaper"
ASSEMBLY = "command"
SYNC_SAFE = False
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


def _warn(message: str) -> None:
    print(f"  wallpaper warning: {message}", file=sys.stderr)


def _apply_wallpaper(path: Path) -> None:
    ok, message = _run_command(_swww_command(str(path)))
    if not ok:
        _warn(f"failed to apply wallpaper {path}: {message}")


def _fallback_to_source(source: Path, reason: str) -> None:
    _warn(f"{reason}; using original wallpaper")
    _apply_wallpaper(source)


def generate(colors: ColorScheme, state: ThemeState) -> list[list[str]]:
    del colors
    if state.filter_wallpaper:
        return []
    return [_swww_command(state.wallpaper)]


def on_apply(colors: ColorScheme, state: ThemeState) -> None:
    if not state.filter_wallpaper:
        return

    source = Path(state.wallpaper).expanduser()
    if not source.is_file():
        _warn(f"source wallpaper does not exist: {source}")
        return

    try:
        filtered = _filtered_wallpaper_path(colors, state)
        if not filtered.is_file():
            if shutil.which("lutgen") is None:
                _fallback_to_source(
                    source,
                    "filter_wallpaper is enabled but 'lutgen' is not installed",
                )
                return

            try:
                filtered.parent.mkdir(parents=True, exist_ok=True)
            except OSError as exc:
                _fallback_to_source(
                    source,
                    f"could not create wallpaper filter cache at {filtered.parent}: {exc}",
                )
                return

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
                _fallback_to_source(
                    source,
                    f"could not generate filtered wallpaper with lutgen: {message}",
                )
                return
        _apply_wallpaper(filtered)
    except Exception as exc:
        _fallback_to_source(
            source,
            f"unexpected error while preparing filtered wallpaper: {exc}",
        )
