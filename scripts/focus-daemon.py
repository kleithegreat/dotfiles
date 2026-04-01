#!/usr/bin/env python3
"""Focus time tracking daemon for Hyprland.

Tracks which application window has focus each second via Hyprland's IPC socket,
persists data to SQLite, and writes a JSON summary for the Quickshell settings pane.

Launched automatically by Hyprland's autostart.
"""

from __future__ import annotations

import calendar
import json
import os
import signal
import socket
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import date, datetime, timedelta
from pathlib import Path

# ── Configuration ─────────────────────────────────────────────────────

DATA_DIR = Path(
    os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"),
    "focustime",
)
DB_PATH = DATA_DIR / "focustime.db"
STATE_PATH = Path(
    os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"),
    "focustime_state.json",
)

EXCLUDED_CLASSES = frozenset({"", "Desktop", "Quickshell"})
LOCKED_CLASS = "__locked__"


# ── Desktop file resolution ──────────────────────────────────────────

_app_cache: dict[str, tuple[str, str]] = {}  # lowercase class -> (Name, Icon)
_cache_loaded = False


def _load_desktop_files() -> None:
    """Parse .desktop files from XDG data directories to build app name/icon cache."""
    global _cache_loaded
    if _cache_loaded:
        return

    data_dirs = [
        os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share")),
        *os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"),
    ]
    for extra in ("/run/current-system/sw/share",
                  str(Path.home() / ".nix-profile" / "share")):
        if extra not in data_dirs:
            data_dirs.append(extra)

    for data_dir in data_dirs:
        app_dir = Path(data_dir) / "applications"
        if not app_dir.is_dir():
            continue
        for desktop in app_dir.rglob("*.desktop"):
            try:
                _parse_desktop(desktop)
            except (OSError, UnicodeDecodeError):
                pass

    _cache_loaded = True


def _parse_desktop(path: Path) -> None:
    name = icon = wm_class = None
    in_entry = False
    for line in path.read_text().splitlines():
        s = line.strip()
        if s.startswith("["):
            in_entry = s == "[Desktop Entry]"
            continue
        if not in_entry or "=" not in s:
            continue
        key, _, val = s.partition("=")
        key, val = key.strip(), val.strip()
        if key == "Name" and name is None:
            name = val
        elif key == "Icon" and icon is None:
            icon = val
        elif key == "StartupWMClass":
            wm_class = val

    if not name:
        return
    icon = icon or ""
    if wm_class:
        _app_cache.setdefault(wm_class.lower(), (name, icon))
    _app_cache.setdefault(path.stem.lower(), (name, icon))


def resolve_app(window_class: str) -> tuple[str, str]:
    """Return (human_name, icon_name) for a window class."""
    _load_desktop_files()
    entry = _app_cache.get(window_class.lower())
    if entry:
        return entry
    return window_class, ""


# ── Database ─────────────────────────────────────────────────────────

def init_db() -> sqlite3.Connection:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH), isolation_level=None)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS daily_totals (
            date      TEXT NOT NULL,
            app_class TEXT NOT NULL,
            seconds   INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (date, app_class)
        );
        CREATE TABLE IF NOT EXISTS hourly_totals (
            date      TEXT NOT NULL,
            hour      INTEGER NOT NULL,
            app_class TEXT NOT NULL,
            seconds   INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (date, hour, app_class)
        );
        CREATE TABLE IF NOT EXISTS minute_totals (
            date         TEXT NOT NULL,
            minute_index INTEGER NOT NULL,
            app_class    TEXT NOT NULL,
            seconds      INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (date, minute_index, app_class)
        );
    """)
    return conn


def accumulate(conn: sqlite3.Connection, app_class: str, now: datetime) -> None:
    """Add one second of focus time to all three tables in a single transaction."""
    d = now.strftime("%Y-%m-%d")
    h = now.hour
    m = h * 60 + now.minute
    conn.execute("BEGIN")
    conn.execute(
        "INSERT INTO daily_totals (date, app_class, seconds) VALUES (?,?,1) "
        "ON CONFLICT(date, app_class) DO UPDATE SET seconds = seconds + 1",
        (d, app_class),
    )
    conn.execute(
        "INSERT INTO hourly_totals (date, hour, app_class, seconds) VALUES (?,?,?,1) "
        "ON CONFLICT(date, hour, app_class) DO UPDATE SET seconds = seconds + 1",
        (d, h, app_class),
    )
    conn.execute(
        "INSERT INTO minute_totals (date, minute_index, app_class, seconds) VALUES (?,?,?,1) "
        "ON CONFLICT(date, minute_index, app_class) DO UPDATE SET seconds = seconds + 1",
        (d, m, app_class),
    )
    conn.execute("COMMIT")


# ── JSON summary ─────────────────────────────────────────────────────

def build_summary(conn: sqlite3.Connection, current_class: str,
                  is_locked: bool) -> dict:
    today = date.today()
    today_str = today.isoformat()

    # Week boundaries (Mon-Sun)
    wd = today.weekday()
    week_start = today - timedelta(days=wd)
    week_end = week_start + timedelta(days=6)

    # Fetch daily sums (excluding locked) for the whole date range we need
    range_start = min(week_start, today - timedelta(days=1))
    daily_sums: dict[str, int] = dict(conn.execute(
        "SELECT date, SUM(seconds) FROM daily_totals "
        "WHERE date BETWEEN ? AND ? AND app_class != ? "
        "GROUP BY date",
        (range_start.isoformat(), week_end.isoformat(), LOCKED_CLASS),
    ).fetchall())

    total = daily_sums.get(today_str, 0)
    yesterday_total = daily_sums.get(
        (today - timedelta(days=1)).isoformat(), 0)

    # Week array
    week = []
    week_nonzero: list[int] = []
    for i in range(7):
        d = week_start + timedelta(days=i)
        d_str = d.isoformat()
        dt = daily_sums.get(d_str, 0)
        week.append({"date": d_str, "day": d.strftime("%a"),
                      "total": dt, "is_target": d == today})
        if dt > 0:
            week_nonzero.append(dt)

    average = (round(sum(week_nonzero) / len(week_nonzero))
               if week_nonzero else 0)
    week_range = (f"{week_start.strftime('%b %-d')} - "
                  f"{week_end.strftime('%b %-d')}")

    # Per-app breakdown (today)
    apps = []
    for cls, secs in conn.execute(
        "SELECT app_class, SUM(seconds) FROM daily_totals "
        "WHERE date = ? AND app_class != ? "
        "GROUP BY app_class ORDER BY SUM(seconds) DESC",
        (today_str, LOCKED_CLASS),
    ):
        if cls in EXCLUDED_CLASSES:
            continue
        name, icon = resolve_app(cls)
        apps.append({
            "class": cls, "name": name, "icon": icon,
            "seconds": secs,
            "percent": round(secs / total * 100, 1) if total > 0 else 0,
        })

    # Current app name
    if is_locked:
        current_name = "Locked"
    elif current_class and current_class not in EXCLUDED_CLASSES:
        current_name = resolve_app(current_class)[0]
    else:
        current_name = ""

    # Month calendar grid (leading None entries align to weekday)
    first_wd, n_days = calendar.monthrange(today.year, today.month)
    month_prefix = today.strftime("%Y-%m-")
    month_sums: dict[str, int] = dict(conn.execute(
        "SELECT date, SUM(seconds) FROM daily_totals "
        "WHERE date LIKE ? AND app_class != ? GROUP BY date",
        (month_prefix + "%", LOCKED_CLASS),
    ).fetchall())
    month: list[dict | None] = [None] * first_wd
    for day in range(1, n_days + 1):
        d = date(today.year, today.month, day)
        d_str = d.isoformat()
        month.append({"date": d_str, "total": month_sums.get(d_str, 0),
                       "is_target": d == today})

    return {
        "selected_date": today_str,
        "total": total,
        "average": average,
        "week_range": week_range,
        "yesterday": yesterday_total,
        "current": current_name,
        "apps": apps,
        "week": week,
        "month": month,
    }


def write_summary(conn: sqlite3.Connection, current_class: str,
                  is_locked: bool) -> None:
    summary = build_summary(conn, current_class, is_locked)
    tmp = STATE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(summary))
    tmp.rename(STATE_PATH)


# ── Lock detection ───────────────────────────────────────────────────

def is_screen_locked() -> bool:
    return subprocess.run(
        ["pgrep", "-x", "hyprlock"], capture_output=True,
    ).returncode == 0


# ── Hyprland IPC ─────────────────────────────────────────────────────

def ipc_socket_path() -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not sig:
        raise RuntimeError("HYPRLAND_INSTANCE_SIGNATURE not set")
    return f"{runtime}/hypr/{sig}/.socket2.sock"


def get_active_class() -> str:
    """Query hyprctl for the currently focused window class."""
    try:
        r = subprocess.run(["hyprctl", "activewindow", "-j"],
                           capture_output=True, text=True, timeout=5)
        if r.returncode == 0 and r.stdout.strip():
            data = json.loads(r.stdout)
            return data.get("class", "") or data.get("initialClass", "")
    except (subprocess.TimeoutExpired, json.JSONDecodeError, OSError):
        pass
    return ""


# ── Daemon ───────────────────────────────────────────────────────────

class FocusDaemon:
    def __init__(self) -> None:
        self._class = ""
        self._lock = threading.Lock()
        self.running = True

    def _set(self, cls: str) -> None:
        with self._lock:
            self._class = cls

    def _get(self) -> str:
        with self._lock:
            return self._class

    # IPC listener (runs in a daemon thread)

    def _listen(self) -> None:
        path = ipc_socket_path()
        while self.running:
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.connect(path)
                sock.settimeout(5.0)
                buf = b""
                while self.running:
                    try:
                        data = sock.recv(4096)
                    except socket.timeout:
                        continue
                    if not data:
                        break
                    buf += data
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        text = line.decode("utf-8", errors="replace")
                        if text.startswith("activewindow>>"):
                            cls = text[14:].split(",", 1)[0]
                            self._set(cls)
            except OSError:
                pass
            finally:
                try:
                    sock.close()
                except OSError:
                    pass
            if self.running:
                time.sleep(2)

    # Main accumulator loop

    def run(self) -> None:
        self._set(get_active_class())

        listener = threading.Thread(target=self._listen, daemon=True)
        listener.start()

        conn = init_db()
        next_tick = time.monotonic() + 1.0

        try:
            while self.running:
                sleep_for = next_tick - time.monotonic()
                if sleep_for > 0:
                    time.sleep(sleep_for)

                now = datetime.now()
                cls = self._get()
                locked = is_screen_locked()

                if locked:
                    accumulate(conn, LOCKED_CLASS, now)
                elif cls:
                    accumulate(conn, cls, now)

                write_summary(conn, cls, locked)

                next_tick += 1.0
                if next_tick <= time.monotonic():
                    next_tick = time.monotonic() + 1.0
        finally:
            conn.close()


# ── Entry point ──────────────────────────────────────────────────────

def main() -> None:
    daemon = FocusDaemon()

    def _stop(sig: int, frame) -> None:
        daemon.running = False

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    daemon.run()


if __name__ == "__main__":
    main()
