# desktopctl — Unified Desktop Daemon & CLI

Reference document for Claude Code agents implementing the native Rust binary
that replaces all Python scripts, shell scripts, and the `apply-theme` CLI in the
dotfiles repo. Read this file before starting any desktopctl-related task.

## Table of Contents

- [Overview](#overview)
- [Motivation](#motivation)
- [Binary Structure](#binary-structure)
- [Daemon Mode](#daemon-mode)
- [CLI Subcommands](#cli-subcommands)
- [Theming System Port](#theming-system-port)
- [Focus Tracking Port](#focus-tracking-port)
- [Solar Scheduling Port](#solar-scheduling-port)
- [Brightness & Display Helpers](#brightness--display-helpers)
- [Hyprland Helpers](#hyprland-helpers)
- [Quickshell Launch](#quickshell-launch)
- [Socket Protocol](#socket-protocol)
- [Quickshell Integration](#quickshell-integration)
- [Nix Packaging](#nix-packaging)
- [Migration & Compatibility](#migration--compatibility)
- [Implementation Plan](#implementation-plan)

---

## Overview

`desktopctl` is a single Rust binary that ships as a Nix package and replaces:

| Current                              | desktopctl equivalent                        |
|--------------------------------------|------------------------------------------|
| `themes/apply-theme` (Python CLI)    | `desktopctl theme {all,set,preset,...}`       |
| `themes/lib/` (Python package)       | Compiled Rust modules                    |
| `scripts/focus-daemon.py`            | `desktopctl daemon` (focus tracking subsystem)|
| `scripts/sun-schedule`               | `desktopctl daemon` (solar scheduling subsystem) + `desktopctl sun {status}` |
| `scripts/brightness-step.sh`         | `desktopctl brightness {up,down}`            |
| `scripts/dim-screen.sh`              | `desktopctl brightness dim`                  |
| `scripts/toggle-float.sh`            | `desktopctl hypr toggle-float`               |
| `scripts/launch-quickshell.sh`       | `desktopctl launch-quickshell`               |
| `config/quickshell/scripts/dir-picker.py` | `desktopctl portal pick-directory`      |

The binary operates in two modes: **daemon** (long-running, launched once at
session start) and **CLI** (short-lived subcommands for theme application,
brightness control, etc.). Some CLI subcommands talk to the daemon over a Unix
socket when they need shared state; others do their work directly and exit.

---

## Motivation

### Performance

- **Theme application latency.** Every Quickshell settings interaction spawns a
  Python process (`apply-theme set <key> <value>`), paying ~50–100ms interpreter
  startup before any work happens. This is perceptible on slider drags and rapid
  dropdown changes. A compiled binary eliminates this.

- **Focus daemon memory.** `focus-daemon.py` keeps a Python interpreter in memory
  (~30–40MB RSS) to do SQLite writes and socket reads once per second. A Rust
  binary does the same work in 2–5MB.

- **Sun-schedule startup.** Runs as a oneshot every 2 hours, paying Python
  startup cost each time for some trig and a few subprocess calls.

### Architectural

- **Shared infrastructure.** Hyprland IPC, D-Bus interaction, perceptual
  brightness math, and XDG path resolution are currently duplicated across Python
  and shell. One binary provides typed wrappers for all of these.

- **Solar scheduling without transient timers.** The daemon can sleep until the
  next solar event and fire directly, replacing the current `systemd-run`
  transient timer approach with internal event scheduling.

- **Foundation for Quickshell socket protocol.** A daemon with a Unix socket
  enables Quickshell to open one persistent connection for theme operations,
  focus-time queries, and brightness updates — replacing the current pattern of
  spawning separate `Process` objects per operation.

### Consolidation

- Eliminates the Python runtime dependency for desktop session services.
- Reduces the `scripts/` directory to zero files.
- Removes the `themes/lib/` Python package and `themes/apply-theme` entry point.
- All executable logic in the repo becomes either Nix config, QML, Lua (neovim),
  or the single `desktopctl` binary.

---

## Binary Structure

### Language & dependencies

Rust, stable toolchain. Key crates (evaluate alternatives during implementation):

- `clap` — CLI argument parsing with subcommand dispatch
- `tokio` — async runtime for the daemon's concurrent subsystems
- `rusqlite` — SQLite for focus tracking (same schema as current Python)
- `serde` / `serde_json` — JSON serialization for theme state, color schemes,
  focustime summaries, and the socket protocol
- `nix` (the crate, not the package manager) — Unix socket, signal handling

No C library dependencies beyond system libc and SQLite. No D-Bus crate is
required initially — the existing `busctl` and `dbus-monitor` subprocess
approach works fine and avoids a heavy dependency. Revisit if the socket protocol
later needs native D-Bus integration.

### Cargo structure

Single binary crate. No workspace, no proc-macros. Internal module organization:

```
src/
├── main.rs                  # clap dispatch
├── daemon/
│   ├── mod.rs               # daemon entry point, subsystem orchestration
│   ├── focus.rs             # focus tracking (Hyprland IPC + SQLite)
│   ├── night_light.rs       # daemon-owned override controller
│   ├── solar.rs             # sunrise/sunset scheduling
│   └── server.rs            # Unix domain socket listener
├── night_light.rs           # night-light CLI + socket client helpers
├── theme/
│   ├── mod.rs               # theme subcommand dispatch
│   ├── schema.rs            # ColorScheme, ThemeState structs
│   ├── resolve.rs           # load/validate color schemes and state
│   ├── orchestrator.rs      # dependency map, target dispatch, assembly
│   └── targets/
│       ├── mod.rs            # target registry
│       ├── alacritty.rs
│       ├── bat.rs
│       ├── cursor.rs
│       ├── ghostty.rs
│       ├── gtk.rs
│       ├── hypr_appearance.rs
│       ├── hyprland.rs
│       ├── neovide.rs
│       ├── neovim.rs
│       ├── qt.rs
│       ├── quickshell.rs
│       ├── snappy_switcher.rs
│       ├── spicetify.rs
│       ├── starship.rs
│       ├── tmux.rs
│       ├── vicinae.rs
│       ├── vscode.rs
│       ├── wallpaper.rs
│       └── zathura.rs
├── brightness.rs            # perceptual brightness math + brightnessctl
├── hypr.rs                  # Hyprland IPC helpers (activewindow, dispatch, etc.)
├── solar.rs                 # NOAA sunrise/sunset algorithm (shared with daemon)
├── portal.rs                # xdg-desktop-portal D-Bus interactions
├── launch.rs                # Quickshell launcher
└── paths.rs                 # XDG path resolution, repo root detection
```

---

## Daemon Mode

```
desktopctl daemon
```

Long-running process, launched once per Hyprland session. Replaces
`focus-daemon.py` in `autostart.conf` and the `sun-scheduler` systemd
timer/service pair.

### Subsystems

The daemon runs three concurrent subsystems under a single tokio runtime:

1. **Focus tracker** — Connects to Hyprland's `.socket2.sock`, listens for
   `activewindow>>` events, accumulates per-second focus data in the shared
   SQLite database at `$XDG_DATA_HOME/desktopctl/desktopctl.db`, and writes the
   JSON summary to `$XDG_RUNTIME_DIR/focustime_state.json`. See
   [Focus Tracking Port](#focus-tracking-port).

2. **Solar scheduler** — Computes sunrise/sunset times at startup (and
   recomputes every few hours or on wake-from-sleep), updates the shared
   daemon-owned night-light controller with the current scheduled state, and
   lets that controller reconcile the effective mode. See
   [Solar Scheduling Port](#solar-scheduling-port).

3. **Socket server** — Listens on
   `$XDG_RUNTIME_DIR/desktopctl.sock` for JSON-framed requests from CLI subcommands
   and Quickshell-facing request surfaces such as `desktopctl night-light`.
   See [Socket Protocol](#socket-protocol).

### Lifecycle

- **Startup:** Open Hyprland IPC socket, initialize SQLite, compute solar times,
  initialize the daemon-owned night-light controller in `auto`, reconcile the
  current effective night-light state, and begin listening on the Unix socket.

- **Shutdown:** On SIGTERM or SIGINT, close the SQLite connection, remove the
  Unix socket file, and exit cleanly. No graceful drain needed — all state is
  persisted to disk on every tick.

- **Crash recovery:** The daemon is stateless across restarts. SQLite data
  persists. The socket file is unlinked on startup if stale (check with connect
  attempt). The focus-time JSON summary is rebuilt from the current second's
  query on the next tick.

### Signal handling

- `SIGTERM`, `SIGINT` → clean shutdown
- `SIGUSR1` → force solar recomputation (useful after timezone/location change)

### Replacing the systemd timer

The `sun-scheduler` systemd service and timer defined in `home/sun-schedule.nix`
are removed entirely. The daemon owns solar scheduling internally. The
`home/sun-schedule.nix` file should be deleted and its import removed from the
home-manager config.

---

## CLI Subcommands

### `desktopctl theme`

Direct port of the current `themes/apply-theme` CLI. It still reads
`themes/colors/*.json` plus the `theme_state` rows in the shared SQLite
database at `$XDG_DATA_HOME/desktopctl/desktopctl.db`, generates and writes
files, and fires reload commands directly. The special case is `dark_hint`:
theme-surface `dark_hint` writes are delegated through the daemon-owned
night-light controller so live policy stays centralized.

```
desktopctl theme all                       # Apply all targets
desktopctl theme sync                      # Apply all sync-safe targets (for home-manager activation)
desktopctl theme colors                    # Apply color-dependent targets
desktopctl theme wallpaper                 # Apply wallpaper target only
desktopctl theme cursor                    # Apply cursor target only
desktopctl theme fonts                     # Apply font-dependent targets
desktopctl theme target <name>             # Apply a single target by name
desktopctl theme set <key> <value>         # Update theme state and apply affected targets
desktopctl theme preset <name>             # Load a preset and apply all targets
desktopctl theme save-preset <name> <json> # Save a preset
desktopctl theme delete-preset <name>      # Delete a preset
desktopctl theme list-schemes              # List available color schemes
desktopctl theme list-presets              # List available presets
desktopctl theme status                    # Show current state
```

The `home.activation.applyTheme` hook changes from:

```nix
PATH="${lib.makeBinPath [pkgs.python3]}:$PATH"
${dotfilesPath}/themes/apply-theme sync
```

to:

```nix
${pkgs.desktopctl}/bin/desktopctl theme sync
```

### `desktopctl brightness`

Replaces `brightness-step.sh` and `dim-screen.sh`.

```
desktopctl brightness up                   # +5% perceptual step
desktopctl brightness down                 # −5% perceptual step
desktopctl brightness dim                  # Gradual dim to 30% (for hypridle)
desktopctl brightness restore              # Wrapper around brightnessctl -r
desktopctl brightness seed                 # Write current value to /tmp/quickshell-brightness
```

The `dim` subcommand writes its PID to `/tmp/dim-screen.pid` and traps cleanup,
exactly as the current shell script does. It calls `brightnessctl -s` before
dimming so `brightnessctl -r` (or `desktopctl brightness restore`) works.

All brightness subcommands write the updated value to
`/tmp/quickshell-brightness` after completion (matching the current contract
with Quickshell's brightness OSD).

### `desktopctl hypr`

Replaces `toggle-float.sh`.

```
desktopctl hypr toggle-float               # Toggle floating + resize/center if unfloating
```

This queries `hyprctl activewindow -j`, checks the `floating` field, and either
runs `hyprctl --batch "dispatch togglefloating ; dispatch resizeactive exact 75%
75% ; dispatch centerwindow 1"` or just `hyprctl dispatch togglefloating`.

Additional Hyprland helper subcommands can be added here in the future.

### `desktopctl launch-quickshell`

Replaces `scripts/launch-quickshell.sh`.

```
desktopctl launch-quickshell               # Parse cursor.conf, export env, exec quickshell
desktopctl launch-quickshell --print-env   # Print XCURSOR_THEME|HYPRCURSOR_THEME|XCURSOR_SIZE
```

Behavior is identical to the current shell script: derive repo root from the
binary's location (or from a known path — see [Nix Packaging](#nix-packaging)),
parse `$XDG_CONFIG_HOME/hypr/cursor.conf` for `env = XCURSOR_THEME,...` lines,
export the variables, and `exec quickshell -p <repo>/config/quickshell`.

The repo root can be resolved by: checking `$desktopctl_REPO` if set, falling back
to `$HOME/repos/dotfiles`. This replaces the shell script's
`$(dirname "$0")/..` trick which won't work for a Nix store binary.

### `desktopctl portal`

Replaces `config/quickshell/scripts/dir-picker.py`.

```
desktopctl portal pick-directory            # Open xdg-desktop-portal directory picker, print path
```

Uses `busctl` and `dbus-monitor` as subprocesses (same approach as the current
Python script). Prints the selected directory path to stdout and exits.

### `desktopctl night-light`

Daemon-backed manual override surface for night light and the live `dark_hint`
policy:

```
desktopctl night-light status             # Show mode, running state, and temperatures
desktopctl night-light status --json      # Machine-readable status for Quickshell
desktopctl night-light on                 # Force night light on at the stored/manual temp
desktopctl night-light on --temp 4300     # Force night light on and update the manual temp
desktopctl night-light off                # Force night light off
desktopctl night-light auto               # Return control to the solar schedule
desktopctl night-light toggle             # Switch between on/off based on current hyprsunset state
```

This subcommand talks to the daemon over `$XDG_RUNTIME_DIR/desktopctl.sock`.
`status` falls back to direct inspection when the daemon is not running, but
live mutations require the daemon because the override state is intentionally
in-memory and non-persistent.

### `desktopctl sun`

Query interface for solar state. The daemon owns the scheduling loop, but this
subcommand provides introspection:

```
desktopctl sun status                      # Print sunrise/sunset times, current state, next events
```

This can either query the daemon over the socket (if running) or compute
independently (if not).

### `desktopctl daemon`

```
desktopctl daemon                          # Start the daemon (foreground)
```

No background/fork mode. The process manager (Hyprland autostart or a systemd
user service) handles backgrounding.

---

## Theming System Port

The existing theming architecture is preserved exactly. The Python code is a
1:1 port to Rust — same concepts, same file layouts, same output formats.

### Preserved invariants

1. **Generators are pure functions.** Each target has a `generate()` function
   that takes `&ColorScheme` and `&ThemeState` and returns a `String` (or
   `Vec<Vec<String>>` for command targets). No file I/O, no side effects.

2. **Three (plus one) assembly strategies.** `import`, `standalone`, `command`,
   and `concat` work identically to the Python implementation. The orchestrator
   handles all file I/O.

3. **Dependency map.** `targets_for_key()` uses the same state-key → target-set
   mapping defined in the current `orchestrator.py`.

4. **`SYNC_SAFE` flag.** Targets marked `SYNC_SAFE = false` (currently `gtk`
   and `wallpaper`) are skipped during `desktopctl theme sync`.

5. **Generated file header.** Non-JSON targets get the same
   `# Generated by apply-theme — do not edit` header.

6. **Same output paths.** Every target writes to the same file paths as the
   current Python implementation. No Quickshell, Neovim, or app config changes
   needed.

### Schema structs

Port `themes/lib/schema.py` to Rust structs with `serde::Deserialize` and
`serde::Serialize`. Key types:

```rust
struct ColorScheme {
    family: String,
    variant: String,     // "dark" or "light" (not constrained to enum)
    colors: NamedColors, // bg, fg, accent, red, green, yellow, blue, purple, etc.
    palette: [String; 16], // 16-entry hex palette
}

struct ThemeState {
    color_scheme: String,
    wallpaper: String,
    filter_wallpaper: bool,
    system_font: String,
    mono_font: String,
    icon_theme: String,
    cursor_theme: String,
    cursor_size: u32,
    font_size: u32,
    mono_font_size: u32,
    dark_hint: bool,
    // Per-target mono font size offsets
    alacritty_mono_font_size_offset: i32,
    ghostty_mono_font_size_offset: i32,
    gtk_mono_font_size_offset: i32,
    neovide_mono_font_size_offset: i32,
    qt_mono_font_size_offset: i32,
    vscode_mono_font_size_offset: i32,
    // Hyprland appearance
    hypr_gaps_in: u32,
    hypr_gaps_out: u32,
    hypr_border_size: u32,
    hypr_rounding: u32,
    hypr_blur_enabled: bool,
    hypr_blur_size: u32,
    hypr_blur_passes: u32,
    hypr_animations_enabled: bool,
}
```

The `ThemeState` struct must preserve the current JSON shape exposed by
`desktopctl theme status --json`, and it must be able to import the legacy
`themes/state.json` payload without changes. Unknown fields should survive a
read-modify-write cycle through the SQLite backend (for example via
`#[serde(flatten)] extra: Map<String, Value>` plus JSON-encoded row values).

Theme state persistence uses a `theme_state(key TEXT PRIMARY KEY, value TEXT
NOT NULL)` table inside `$XDG_DATA_HOME/desktopctl/desktopctl.db`. Each `value`
cell stores one JSON-encoded field value so strings, integers, booleans, and
future nested objects round-trip without schema changes. Fresh installs seed the
table from compiled defaults, and first access imports `themes/state.json` when
that legacy file still exists and the table is empty.

`ThemeState` should provide a `mono_font_size_for(&self, target: &str) -> u32`
method that returns `self.mono_font_size + offset` for the given target name,
matching the current Python helper.

### Target registry

Each target is a Rust module in `src/theme/targets/`. The registry is built at
compile time via a `register!` macro or a simple hand-written match/map in
`src/theme/targets/mod.rs` that maps target names to their metadata and
`generate` function pointers.

Each target module exports:

```rust
pub const TARGET_NAME: &str = "alacritty";
pub const ASSEMBLY: Assembly = Assembly::Import;
pub const OUTPUT_PATH: &str = "~/.config/alacritty/theme.toml";
pub const COMMENT: &str = "#";
pub const RELOAD_CMD: Option<&[&str]> = None;
pub const SYNC_SAFE: bool = true;
// For concat targets:
pub const BASE_PATH: Option<&str> = Some("~/repos/dotfiles/config/alacritty/alacritty.toml");
// For targets with extra outputs (like qt):
pub const EXTRA_OUTPUTS: &[&str] = &[];

pub fn generate(colors: &ColorScheme, state: &ThemeState) -> String { ... }

// Optional hooks:
pub fn persist(colors: &ColorScheme, state: &ThemeState) -> Result<()> { ... }
pub fn on_apply(colors: &ColorScheme, state: &ThemeState) -> Result<()> { ... }
```

The orchestrator calls `generate()` → writes via assembly strategy → calls
`persist()` if present → calls `on_apply()` if present (only when
`runtime=true`), exactly matching the current Python flow.

### Wallpaper target specifics

The wallpaper target has special behavior:

- When `filter_wallpaper` is false, `generate()` returns a direct `awww img`
  command.
- When `filter_wallpaper` is true, `on_apply()` computes a cache key from the
  wallpaper path and active palette, optionally runs `lutgen apply --cache`,
  writes filtered output under `~/.cache/apply-theme/wallpaper/`, then applies
  the result.

This logic should be ported faithfully. The `lutgen` binary is called as a
subprocess — do not reimplement its image processing.

### VS Code target specifics

The `vscode` target's `persist()` function edits VS Code's SQLite state database
to re-enable theme extensions. This needs `rusqlite` access in the target's
persist hook. Port the exact same SQL operations.

---

## Focus Tracking Port

Direct port of `scripts/focus-daemon.py`. The daemon's focus subsystem:

### Hyprland IPC connection

Connect to `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`
(the event socket). Parse `activewindow>>class,title` lines to track the
current focused window class. Reconnect with backoff on socket errors (matching
the current 2-second retry sleep).

On startup, also query the current active window via `hyprctl activewindow -j`
to seed the initial state.

### SQLite schema

Use the shared database at `$XDG_DATA_HOME/desktopctl/desktopctl.db`. The focus
tables keep the same schema the Python daemon created:

```sql
CREATE TABLE IF NOT EXISTS daily_totals (
    date TEXT NOT NULL,
    app_class TEXT NOT NULL,
    seconds INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (date, app_class)
);

CREATE TABLE IF NOT EXISTS hourly_totals (
    date TEXT NOT NULL,
    hour INTEGER NOT NULL,
    app_class TEXT NOT NULL,
    seconds INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (date, hour, app_class)
);

CREATE TABLE IF NOT EXISTS minute_totals (
    date TEXT NOT NULL,
    minute_index INTEGER NOT NULL,
    app_class TEXT NOT NULL,
    seconds INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (date, minute_index, app_class)
);
```

Accumulation: every second, one transaction UPSERTs one second into all three
tables. When the screen is locked (detected via `pgrep -x hyprlock`),
accumulate under the `__locked__` class instead. When the screen is unlocked
and the current class is empty, skip the SQLite write for that tick.

Migration: if the legacy focus database at
`$XDG_DATA_HOME/focustime/focustime.db` exists and the shared database's focus
tables are empty, the daemon should copy the existing rows into
`desktopctl.db`, then tell the user they can delete the old
`$XDG_DATA_HOME/focustime/` directory.

### Desktop file resolution

Parse `.desktop` files from XDG data directories to build a
`window_class → (app_name, icon_name)` lookup cache. Scan the same paths as the
current Python implementation:

- `$XDG_DATA_HOME/applications/`
- Directories from `$XDG_DATA_DIRS`
- `/run/current-system/sw/share/applications/`
- `$HOME/.nix-profile/share/applications/`

Match on `StartupWMClass` first, then fall back to the `.desktop` file stem
(lowercased). Cache is built once at startup.

### JSON summary output

Write to `$XDG_RUNTIME_DIR/focustime_state.json` (atomic write via temp file +
rename). The JSON format must exactly match the current output so the Quickshell
`SettingsFocusTimePane` works without changes:

```json
{
  "selected_date": "2026-04-02",
  "total": 14523,
  "average": 12800,
  "week_range": "Mar 31 - Apr 6",
  "yesterday": 11200,
  "current": "Alacritty",
  "apps": [
    {"class": "Alacritty", "name": "Alacritty", "icon": "Alacritty", "seconds": 5400, "percent": 37.2},
    ...
  ],
  "week": [
    {"date": "2026-03-31", "day": "Mon", "total": 12000, "is_target": false},
    ...
  ],
  "month": [
    null, null, null,
    {"date": "2026-04-01", "total": 11200, "is_target": false},
    {"date": "2026-04-02", "total": 14523, "is_target": true},
    ...
  ]
}
```

The `month` array is prefixed with `null` entries for the weekday offset of the
first day of the month (Monday = 0). The `week` array always contains all seven
days from Monday through Sunday, with `0` totals for missing days. `apps` is
sorted descending by seconds, excluding `__locked__` and classes in
`EXCLUDED_CLASSES` (`""`, `"Desktop"`, `"Quickshell"`). `total`, `yesterday`,
`week[*].total`, and `month[*].total` exclude `__locked__` only; they do not
hide `Desktop` or `Quickshell`.

---

## Solar Scheduling Port

Port of `scripts/sun-schedule`. The daemon's solar subsystem replaces both the
Python script and the systemd timer.

### NOAA solar algorithm

Port the `sun_times(lat, lon, date)` function that implements the NOAA solar
calculator. Returns `(sunrise, sunset)` as UTC timestamps for a given date and
location. This is pure math — no external dependencies.

### Location resolution

1. Try reading the cached JSON at `$XDG_CACHE_HOME/sun-schedule/location.json`.
2. If missing or invalid, try running `where-am-i` (GeoClue2) with a 10-second
   timeout and cache the result.
3. Fall back to hardcoded College Station, TX (30.6280, -96.3344).

### Event loop

Instead of transient systemd timers, the daemon computes the next solar event,
stores the resulting scheduled state, and lets the shared night-light
controller decide the live outcome:

```
loop {
    compute sunrise, sunset for today and tomorrow
    compute dark_on (23:00 local)
    determine next event = min(next_sunrise, next_sunset, next_dark_on)
    update shared scheduled solar status
    reconcile effective mode (auto/on/off)
    sleep until next event
}
```

The controller applies the live state with this contract:

- **`auto`:** `hyprsunset` follows the solar night window, and `dark_hint`
  follows the solar dark window.
- **`on`:** `hyprsunset` stays on at the stored manual temperature, and
  `dark_hint` is forced to `true`.
- **`off`:** `hyprsunset` stays off, and `dark_hint` is forced to `false`.

The daemon persists `dark_hint` in-process through the theming module rather
than spawning a subprocess, so the live policy owner stays inside the daemon
while the GTK write path remains unchanged.

Recompute solar times every 2 hours (to handle location/timezone drift) and
also on `SIGUSR1`. The solar scheduler keeps recomputing while the mode is
`on` or `off`, so `status` stays current and returning to `auto` can apply the
right state immediately.

---

## Brightness & Display Helpers

### Perceptual brightness model

Both `brightness up/down` and `brightness dim` operate in perceptual space using
gamma 2.2 correction, matching the current shell scripts:

```
perceived = (raw / max) ^ (1 / 2.2)
raw = max * perceived ^ 2.2
```

The backlight device is auto-detected from `/sys/class/backlight/` (first
entry), but can be overridden with `--device` if needed. The current scripts
hardcode `intel_backlight`.

### `brightness up` / `brightness down`

Single 5% perceptual step. Calls `brightnessctl -d <device> s <raw>` and writes
the result to `/tmp/quickshell-brightness`.

### `brightness dim`

Gradual dim over 20 steps with 50ms delay each (total ~1 second), from current
brightness to 30% of current. Writes PID to `/tmp/dim-screen.pid`. Calls
`brightnessctl -d <device> -s` first to save state for restore.

### `brightness restore`

Calls `brightnessctl -r` and writes the restored value to
`/tmp/quickshell-brightness`.

### `brightness seed`

Calls `brightnessctl -d <device> -m` and writes to `/tmp/quickshell-brightness`.
Replaces the `brightnessctl -d intel_backlight -m > /tmp/quickshell-brightness`
line in `autostart.conf`.

---

## Hyprland Helpers

### `hypr toggle-float`

Port of `scripts/toggle-float.sh`:

1. Run `hyprctl activewindow -j`, parse JSON.
2. If `floating == false`: run `hyprctl --batch "dispatch togglefloating ;
   dispatch resizeactive exact 75% 75% ; dispatch centerwindow 1"`.
3. If `floating == true`: run `hyprctl dispatch togglefloating`.

### Shared Hyprland IPC module

`src/hypr.rs` provides:

- `active_window() -> Result<WindowInfo>` — parse `hyprctl activewindow -j`
- `dispatch(args: &[&str]) -> Result<()>` — run `hyprctl dispatch ...`
- `batch(commands: &[&str]) -> Result<()>` — run `hyprctl --batch ...`
- `keyword(key: &str, value: &str) -> Result<()>` — run `hyprctl keyword ...`
- `socket2_connect() -> Result<UnixStream>` — connect to the Hyprland event
  socket for the daemon's focus listener

---

## Quickshell Launch

### `launch-quickshell`

Port of `scripts/launch-quickshell.sh`:

1. Determine repo root: `$desktopctl_REPO` env var, falling back to
   `$HOME/repos/dotfiles`.
2. Read `$XDG_CONFIG_HOME/hypr/cursor.conf` (or
   `$HOME/.config/hypr/cursor.conf`).
3. Parse `env = XCURSOR_THEME,...`, `env = XCURSOR_SIZE,...`, and
   `env = HYPRCURSOR_THEME,...` lines.
4. Export the parsed values as environment variables.
5. If `--print-env` flag is set, print `XCURSOR_THEME|HYPRCURSOR_THEME|XCURSOR_SIZE`
   and exit.
6. Otherwise, `exec quickshell -p <repo>/config/quickshell`.

The `exec` replaces the current process, so `desktopctl launch-quickshell` does not
return.

---

## Socket Protocol

The daemon listens on `$XDG_RUNTIME_DIR/desktopctl.sock`. The protocol is
newline-delimited JSON (one JSON object per line, `\n`-terminated).

### Request format

```json
{"method": "<method_name>", "params": { ... }}
```

### Response format

```json
{"ok": true, "data": { ... }}
{"ok": false, "error": "message"}
```

### Current methods

| Method | Params | Response | Description |
|--------|--------|----------|-------------|
| `ping` | none | `{"pong": true}` | Health check |
| `night_light.status` | none | `{mode, running, temperature, target_temperature, dark_hint, scheduled_running, scheduled_dark_hint}` | Current daemon-owned night-light state |
| `night_light.set` | `{mode, temperature?}` | Same as `night_light.status` | Update the daemon-owned mode and optional manual temperature |
| `night_light.toggle` | none | Same as `night_light.status` | Switch between `on` and `off` based on the current `hyprsunset` state |

Additional theme, focus, and subscription methods can still be added later if
Quickshell moves more domains onto a persistent socket connection.

---

## Quickshell Integration

### Phase 1 — Drop-in replacement (no Quickshell changes)

All current `Process` commands in Quickshell continue to work by changing only
the binary path:

- `["/home/kevin/repos/dotfiles/themes/apply-theme", "set", key, value]`
  → `["desktopctl", "theme", "set", key, value]`
- `["cat", "/home/kevin/repos/dotfiles/themes/state.json"]`
  → `["desktopctl", "theme", "status", "--json"]`
- The `bash -c "for f in .../themes/colors/*.json..."` process
  → `["desktopctl", "theme", "list-schemes", "--json"]`
- The `bash -c "for f in .../themes/presets/*.json..."` process
  → `["desktopctl", "theme", "list-presets", "--json"]`

Night light is the first domain that moved beyond a drop-in replacement:
`DisplayService.qml` now polls `desktopctl night-light status --json` and sends
`desktopctl night-light on/off` requests instead of managing `hyprsunset`
directly.

The existing `jq`-based color scheme listing in `SettingsPopup.qml` is replaced
by a dedicated JSON output from `desktopctl theme list-schemes --json` that returns
the exact shape the QML code expects:

```json
[
  {
    "schemeName": "gruvbox-dark",
    "family": "gruvbox",
    "variant": "dark",
    "bg": "#282828", "fg": "#ebdbb2",
    "accent": "#458588", "red": "#cc241d",
    "green": "#98971a", "blue": "#458588",
    "yellow": "#d79921", "purple": "#b16286"
  },
  ...
]
```

Similarly, `desktopctl theme list-presets --json` returns:

```json
[
  {"name": "gruvbox-forest", "color_scheme": "gruvbox-dark", "wallpaper": "..."},
  ...
]
```

And `desktopctl theme status --json` returns the raw theme-state JSON shape in
the canonical field order.

### Phase 2 — Socket integration (future)

Replace the `Process`-based calls in `SettingsPopup.qml` and `shell.qml` with a
persistent socket connection to the daemon. This eliminates per-operation process
spawn overhead entirely. Design this in a separate spec when Phase 1 is stable.

---

## Nix Packaging

### Package definition

Add a Nix package for `desktopctl` in the flake, built with `rustPlatform.buildRustPackage`
(or `crane`, evaluate during implementation). The package goes in
`packages/desktopctl/default.nix` or similar.

The binary should be available as `pkgs.desktopctl` in the flake's overlay so it can
be referenced in home-manager config and system config.

### Home-manager integration

Replace script installations in `home/default.nix`:

```nix
# Remove these:
home.file.".local/bin/dim-screen.sh" = { ... };
home.file.".local/bin/brightness-step.sh" = { ... };
home.file.".local/bin/toggle-float.sh" = { ... };
home.file.".local/bin/focus-daemon.py" = { ... };

# desktopctl is on PATH via the system/user package set
```

Replace the activation hook:

```nix
home.activation.applyTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
  ${pkgs.desktopctl}/bin/desktopctl theme sync
'';
```

Remove `home/sun-schedule.nix` and its import.

### Autostart changes

In `config/hypr/autostart.conf`:

```conf
# Before:
exec-once = brightnessctl -d intel_backlight -m > /tmp/quickshell-brightness
exec-once = ~/repos/dotfiles/scripts/launch-quickshell.sh
exec-once = ~/.local/bin/focus-daemon.py

# After:
exec-once = desktopctl brightness seed
exec-once = desktopctl daemon &
exec-once = desktopctl launch-quickshell
```

Note: the daemon is backgrounded with `&` because `launch-quickshell` calls
`exec` and replaces the shell process. Alternatively, the daemon can be a
systemd user service (preferred for restart handling):

```nix
systemd.user.services.desktopctl = {
  Unit.Description = "desktopctl desktop daemon";
  Unit.After = [ "hyprland-session.target" ];
  Service = {
    Type = "simple";
    ExecStart = "${pkgs.desktopctl}/bin/desktopctl daemon";
    Restart = "on-failure";
    RestartSec = 2;
  };
  Install.WantedBy = [ "hyprland-session.target" ];
};
```

### Keybind changes

In `config/hypr/keybinds.conf`:

```conf
# Before:
binde = , XF86MonBrightnessUp, exec, ~/.local/bin/brightness-step.sh up
binde = , XF86MonBrightnessDown, exec, ~/.local/bin/brightness-step.sh down

# After:
binde = , XF86MonBrightnessUp, exec, desktopctl brightness up
binde = , XF86MonBrightnessDown, exec, desktopctl brightness down
```

### Hypridle changes

In `config/hypr/hypridle.conf`, the dim listener changes from
`~/.local/bin/dim-screen.sh` to `desktopctl brightness dim`, and the restore from
`brightnessctl -r` to `desktopctl brightness restore`.

### March optimization

If `desktopctl` is in the set of packages that benefit from `-march` optimization
(it runs compiled code in a tight loop for focus tracking), add it to the
optimized package set in `overlays/march-optimized.nix`. The binary does not
run target binaries during its build, so it should be optimized but **not**
tagged with `requiredSystemFeatures`.

---

## Migration & Compatibility

### Parallel operation

During development, `desktopctl` and the Python scripts can coexist. The theming
system still reads the same `themes/colors/*.json` palette files, but mutable
theme state now lives in `$XDG_DATA_HOME/desktopctl/desktopctl.db`. If a legacy
`themes/state.json` file is present and the `theme_state` table is empty,
`desktopctl` imports it on first access and tells the user they can delete the
file. Focus-time data follows the same pattern: the daemon migrates rows from
`$XDG_DATA_HOME/focustime/focustime.db` into `desktopctl.db` when the shared
focus tables are empty.

### Validation

Before declaring a target ported, verify that `desktopctl theme target <name>`
produces byte-identical output to `apply-theme target <name>` for the same
state. A test script can diff the outputs across all targets.

### Files removed after migration

Once `desktopctl` is the sole implementation:

- `themes/apply-theme` (Python entry point)
- `themes/lib/` (entire Python package)
- `scripts/focus-daemon.py`
- `scripts/sun-schedule`
- `scripts/brightness-step.sh`
- `scripts/dim-screen.sh`
- `scripts/toggle-float.sh`
- `scripts/launch-quickshell.sh`
- `config/quickshell/scripts/dir-picker.py`
- `home/sun-schedule.nix`

The `themes/colors/` and `themes/presets/` files remain — they are data, not
code. Mutable theme state now lives in
`$XDG_DATA_HOME/desktopctl/desktopctl.db`.

---

## Implementation Plan

### Dependency graph

```
Phase 0: Foundation (sequential)
├── Cargo project scaffold + clap CLI skeleton
├── src/paths.rs (XDG path resolution, repo root detection)
├── src/hypr.rs (Hyprland IPC helpers)
├── Nix package definition (buildRustPackage, added to flake overlay)
└── Verify: `desktopctl --help` works from a nixos-rebuild

Phase 1: Shell script ports (all parallel — independent of each other)
├── Agent A: brightness.rs (up, down, dim, restore, seed)
├── Agent B: hypr toggle-float
├── Agent C: launch-quickshell
└── Agent D: portal pick-directory

Phase 2: Focus tracking (sequential, after Phase 0)
├── daemon/focus.rs (Hyprland socket listener + SQLite + JSON summary)
├── daemon/mod.rs (tokio runtime, signal handling, subsystem orchestration)
├── Verify: JSON output matches focus-daemon.py exactly
└── Verify: Quickshell FocusTimePane renders correctly

Phase 3: Solar scheduling (parallel with Phase 2, after Phase 0)
├── solar.rs (NOAA algorithm port)
├── daemon/night_light.rs (override controller, hyprsunset lifecycle, dark_hint arbitration)
├── daemon/solar.rs (event loop, solar recomputation, controller reconciliation)
└── Verify: sunrise/sunset times match the Python implementation

Phase 4: Theming — schema & orchestrator (sequential, after Phase 0)
├── theme/schema.rs (ColorScheme, ThemeState with serde)
├── theme/resolve.rs (load/validate colors and state)
├── theme/orchestrator.rs (dependency map, assembly strategies, dispatch)
├── theme/targets/mod.rs (registry)
└── Verify: can load current theme state and color schemes without error

Phase 5: Theming — target generators (all parallel, after Phase 4)
├── Agent E: alacritty + bat + zathura (simple import/standalone targets)
├── Agent F: ghostty + starship + tmux + vicinae (concat targets)
├── Agent G: hyprland + hypr_appearance (standalone targets)
├── Agent H: quickshell + neovim + neovide (standalone JSON/Lua targets)
├── Agent I: gtk + cursor + wallpaper (command targets, SYNC_SAFE=false)
├── Agent J: qt + snappy_switcher (concat targets with hooks)
├── Agent K: vscode + spicetify (concat targets, vscode has SQLite persist)
└── Verify: byte-identical output for all targets vs Python implementation

Phase 6: Theme CLI (sequential, after Phase 5)
├── theme/mod.rs (subcommand dispatch: all, set, preset, list-*, status)
├── --json output modes for list-schemes, list-presets, status
└── Verify: full theme cycle works from CLI

Phase 7: Daemon socket server (sequential, after Phases 2, 3, 6)
├── daemon/server.rs (Unix socket listener, JSON protocol)
├── Initial methods: ping, focus.summary, sun.status
└── Verify: `desktopctl sun status` queries the daemon successfully

Phase 8: Integration (sequential, after all above)
├── Update home/default.nix (remove script installations, update activation hook)
├── Remove home/sun-schedule.nix
├── Update autostart.conf, keybinds.conf, hypridle.conf
├── Update SettingsPopup.qml (change apply-theme paths to desktopctl)
├── Update shell.qml (change apply-theme path to desktopctl)
├── Full end-to-end test
└── Remove Python scripts and themes/lib/

Phase 9: Quickshell socket integration (future, after Phase 8 stabilizes)
├── Define socket protocol extensions for theme operations
├── Implement Quickshell socket client in QML
└── Replace Process-based theme calls with socket calls
```

### Prompt style for Claude Code

Each phase should be a separate Claude Code prompt. Follow the existing prompt
conventions:

- Describe the problem and desired behavior, not the exact implementation
- Reference this spec and the existing code being ported
- Encourage reading the source being replaced before writing any code
- Discourage assumptions — especially about file formats, field names, and output
  shapes
- Scope to one concern per prompt where possible
- For target generators (Phase 5), each agent gets one prompt with 2–4 related
  targets grouped by assembly strategy

### Example Phase 0 prompt

> Scaffold a Rust binary crate called `desktopctl` in `packages/desktopctl/` within the
> dotfiles repo. Read `docs/desktopctl/SPEC.md` for the full specification.
>
> For this phase, implement:
> - Cargo.toml with dependencies: clap (derive), tokio, serde, serde_json
> - src/main.rs with clap subcommand skeleton (all subcommands listed in the spec,
>   but only `--help` needs to work)
> - src/paths.rs with repo root detection ($desktopctl_REPO or $HOME/repos/dotfiles)
>   and XDG path helpers
> - src/hypr.rs with the Hyprland IPC helpers described in the spec
> - A Nix package definition using rustPlatform.buildRustPackage, added to the
>   flake overlay so `pkgs.desktopctl` is available
>
> Do not implement any subcommand logic beyond the CLI skeleton. Read the existing
> shell scripts and Python code referenced in the spec to understand the interfaces
> that will be ported in later phases.

---

## Agent Quick-Reference

When starting a task, read these sections:

1. [Binary Structure](#binary-structure) — always
2. The specific section for the subsystem you are implementing
3. [Migration & Compatibility](#migration--compatibility) — for any integration work
4. [Nix Packaging](#nix-packaging) — if your task touches the Nix config

### Common mistakes to avoid

- **Don't use external crates where subprocesses suffice.** `brightnessctl`,
  `hyprctl`, `busctl`, `dbus-monitor`, `awww`, `gsettings`, `lutgen`,
  `hyprsunset`, `ps`, and `pkill` are all called as subprocesses. Do not
  replace them with native Rust reimplementations.
- **Don't change output formats.** Every file the theming system writes, every
  JSON summary the focus daemon produces, and every path must exactly match the
  current implementation. Quickshell, Neovim, and all themed applications read
  these files.
- **Don't hardcode `/home/kevin/`.** Use the path resolution in `src/paths.rs`.
  The repo root comes from `$desktopctl_REPO` or `$HOME/repos/dotfiles`.
- **Don't add D-Bus crate dependencies.** Use `busctl` and `dbus-monitor` as
  subprocesses. The current approach works and avoids a heavy compile-time
  dependency.
- **Don't make the daemon required for CLI operations.** `desktopctl theme set ...`
  must work even if the daemon is not running. The socket is an optimization
  for Quickshell, not a dependency.
- **Don't use nightly Rust.** Stable toolchain only.
- **Preserve round-trip fidelity for theme state.** Unknown fields must survive
  a read-modify-write cycle through `desktopctl.db`. Use JSON-encoded row values
  and `serde_json::Map<String, Value>` for the internal representation if
  `#[serde(flatten)]` doesn't handle this cleanly.
