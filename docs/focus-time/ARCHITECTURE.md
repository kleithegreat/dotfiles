# Focus Time Architecture

## Scope

Current implementation map for the focus-time subsystem as of 2026-04-08.

## Runtime Topology

1. Home Manager installs `desktopctl` into the user environment through
   `home/default.nix:33-45`.
2. Hyprland starts `desktopctl daemon` once per session through
   `config/hypr/autostart.conf:6-8`.
3. `desktopctl/src/daemon/mod.rs:19-100` starts the focus tracker alongside the
   solar scheduler and socket server under one tokio runtime.
4. The focus tracker owns both runtime artifacts:
   `$XDG_DATA_HOME/desktopctl/desktopctl.db` and
   `${XDG_RUNTIME_DIR:-/run/user/$UID}/focustime_state.json`.
5. `SettingsFocusTimePane.qml` still polls the JSON summary every 3 seconds,
   derives missing/stale/parse-error state locally, and does not talk to SQLite
   or the daemon socket directly.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `home/default.nix` | Installs `desktopctl` and the Hyprland config fragments that source `autostart.conf` | `home/default.nix:37-49`, `home/default.nix:196-211` |
| `config/hypr/autostart.conf` | Starts `desktopctl daemon` during session startup | `config/hypr/autostart.conf:6-8` |
| `desktopctl/src/daemon/mod.rs` | Builds the tokio runtime and starts focus, solar, and socket subsystems together | `desktopctl/src/daemon/mod.rs:19-100` |
| `desktopctl/src/daemon/focus.rs` | Implements the full focus producer: shared-DB initialization, legacy focus-data migration, per-second accumulation, daily minute-table retention, reconnect seeding, socket re-resolution, desktop-file cache, summary building, and atomic JSON replacement | `desktopctl/src/daemon/focus.rs:20-577`, `desktopctl/src/daemon/focus.rs:618-800` |
| `config/quickshell/popups/SettingsPopup.qml` | Still mounts the focus-time pane as settings category `6`, after the Notifications pane | `config/quickshell/popups/SettingsPopup.qml:63-72`, `config/quickshell/popups/SettingsPopup.qml:1007-1020`, `config/quickshell/popups/SettingsPopup.qml:1066-1068` |
| `config/quickshell/popups/settings/SettingsFocusTimePane.qml` | Polls the JSON summary, classifies missing/stale/parse failures, holds charts behind a first-fresh-payload gate, and renders totals, charts, and app breakdowns only for fresh data | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:15-94`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:134-434` |

No other repo file reads `focustime_state.json` directly.

## Producer Internals

| Responsibility | Current implementation | Evidence |
| --- | --- | --- |
| Runtime path selection | The daemon uses the shared XDG helpers, including `paths::db_path()` for the unified SQLite file, falls back to `/run/user/$UID` for the JSON summary when needed, and shares that same runtime-dir fallback with the Quickshell consumer | `desktopctl/src/paths.rs:34-66`, `desktopctl/src/daemon/focus.rs:76-110`, `desktopctl/src/daemon/focus.rs:486-493` |
| SQLite initialization | WAL mode plus `CREATE TABLE IF NOT EXISTS` for `daily_totals`, `hourly_totals`, and `minute_totals`, all inside `desktopctl.db` | `desktopctl/src/daemon/focus.rs:77-103` |
| Legacy data migration | On first access, the daemon imports rows from the legacy `focustime.db` when the shared focus tables are empty and then prints a cleanup hint | `desktopctl/src/daemon/focus.rs:131-243` |
| Per-second accumulation | One transaction increments the current class or `__locked__` in all three tables once per second | `desktopctl/src/daemon/focus.rs:20-63`, `desktopctl/src/daemon/focus.rs:245-272` |
| Retention | At the first tick of each new local day, the daemon deletes `minute_totals` rows older than 90 days and leaves `daily_totals` and `hourly_totals` untouched | `desktopctl/src/daemon/focus.rs:44-48`, `desktopctl/src/daemon/focus.rs:505-508` |
| Summary building | The daemon computes today's totals, yesterday, the Monday-Sunday week, the current-month heatmap, and today's app list from SQLite; aggregate queries now exclude `__locked__`, `Desktop`, and `Quickshell`, and the root summary carries `last_updated` | `desktopctl/src/daemon/focus.rs:290-485`, `desktopctl/src/daemon/focus.rs:729-800` |
| JSON output | The summary is serialized to Python-compatible JSON and atomically renamed into place via `focustime_state.tmp` | `desktopctl/src/daemon/focus.rs:275-287`, `desktopctl/src/daemon/focus.rs:742-800` |
| Lock detection | `pgrep -x hyprlock` still defines the locked state | `desktopctl/src/daemon/focus.rs:497-503` |
| Focus updates | The daemon seeds from `hyprctl activewindow -j` at startup and again after each successful socket reconnect, re-resolves the socket path on every reconnect loop, and then listens for `activewindow>>` lines on Hyprland's `.socket2.sock` with a fixed reconnect sleep | `desktopctl/src/hypr.rs:22-25`, `desktopctl/src/hypr.rs:64-145`, `desktopctl/src/daemon/focus.rs:20-28`, `desktopctl/src/daemon/focus.rs:522-562` |
| App metadata cache | `.desktop` files are indexed by `StartupWMClass` and file stem under XDG data dirs plus the common Nix application directories | `desktopctl/src/daemon/focus.rs:617-727` |

## Consumer Internals

| Concern | Current implementation | Evidence |
| --- | --- | --- |
| Read path | A `Process` runs `bash -c 'state_root="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"; state_path="$state_root/focustime_state.json"; [ -f "$state_path" ] || exit 3; cat -- "$state_path"'` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:58-60` |
| Parse behavior | Exit code `3` maps to "The focus time daemon is not running"; other read failures or parse failures map to "Unable to read focus time data"; parsed summaries older than 5 seconds map to "Focus daemon has not updated recently"; charts remain hidden until the first fresh payload primes `chartVisualsReady` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:34-40`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:64-95`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:143-171` |
| Poll cadence | The pane triggers an immediate read on mount, then polls every 3000 ms while idle | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:86-90` |
| Derived fields | The pane projects fresh JSON into totals, current app, app list, week series, month heatmap, and week range; `last_updated` is consumed only by the freshness gate; chart cell sizes and label sizes now scale from theme metrics instead of fixed pixel constants | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:15-53`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:218-434` |

## External Runtime Surfaces

| Path or command | Owner | Current usage | Evidence |
| --- | --- | --- | --- |
| `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` and `/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` | Hyprland | Focus tracker prefers the runtime socket, falls back to `/tmp/hypr`, and can rediscover the newest available socket during reconnects | `desktopctl/src/hypr.rs:64-145`, `desktopctl/src/daemon/focus.rs:522-560` |
| `hyprctl activewindow -j` | Hyprland CLI | Used for the startup snapshot of the current focused class and for each successful socket reconnect reseed | `desktopctl/src/hypr.rs:22-25`, `desktopctl/src/daemon/focus.rs:20-24`, `desktopctl/src/daemon/focus.rs:534-536` |
| `pgrep -x hyprlock` | Process table / `hyprlock` | Used as the lock-state probe every second | `desktopctl/src/daemon/focus.rs:497-503` |
| `XDG_DATA_HOME/applications` and `XDG_DATA_DIRS/*/applications` | Desktop-entry providers | Used for app-name and icon lookup | `desktopctl/src/daemon/focus.rs:617-727` |
| `/run/current-system/sw/share/applications` and `~/.nix-profile/share/applications` | Nix package profiles | Appended when absent from `XDG_DATA_DIRS` | `desktopctl/src/daemon/focus.rs:632-639` |
