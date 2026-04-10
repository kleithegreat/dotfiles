# Focus Time Architecture

## Scope

Current implementation map for the focus-time subsystem as of 2026-04-08.

## Runtime Topology

1. Home Manager installs `desktopctl` into the user environment through the
   `home.packages` list in `home/default.nix`.
2. Hyprland starts `desktopctl daemon` once per session through the
   `exec-once = desktopctl daemon &` entry in `config/hypr/autostart.conf`.
3. The daemon bootstrap in `desktopctl/src/daemon/mod.rs` starts the focus
   tracker alongside the solar scheduler and socket server under one tokio
   runtime.
4. The focus tracker owns both runtime artifacts:
   `$XDG_DATA_HOME/desktopctl/desktopctl.db` and
   `${XDG_RUNTIME_DIR:-/run/user/$UID}/focustime_state.json`.
5. `SettingsFocusTimePane.qml` still polls the JSON summary every 3 seconds,
   derives missing/stale/parse-error state locally, and does not talk to SQLite
   or the daemon socket directly.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `home/default.nix` | Installs `desktopctl` and the Hyprland config fragments that source `autostart.conf` | The `home.packages` list plus the shared `xdg.configFile."hypr/autostart.conf"` mapping in `home/default.nix` |
| `config/hypr/autostart.conf` | Starts `desktopctl daemon` during session startup | The `exec-once = desktopctl daemon &` entry |
| `desktopctl/src/daemon/mod.rs` | Builds the tokio runtime and starts focus, solar, and socket subsystems together | The daemon `run()` / `run_async()` bootstrap |
| `desktopctl/src/daemon/focus.rs` | Implements the full focus producer: shared-DB initialization, legacy focus-data migration, per-second accumulation, daily minute-table retention, reconnect seeding, socket re-resolution, desktop-file cache, summary building, and atomic JSON replacement | The focus tracker implementation and JSON summary writer in `desktopctl/src/daemon/focus.rs` |
| `config/quickshell/popups/SettingsPopup.qml` | Still mounts the focus-time pane as settings category `6`, after the Notifications pane | The `categoryNames` list and settings-detail loader wiring in `config/quickshell/popups/SettingsPopup.qml` |
| `config/quickshell/popups/settings/SettingsFocusTimePane.qml` | Polls the JSON summary, classifies missing/stale/parse failures, holds charts behind a first-fresh-payload gate, and renders totals, charts, and app breakdowns only for fresh data | The pane state machine and chart rendering in `config/quickshell/popups/settings/SettingsFocusTimePane.qml` |

No other repo file reads `focustime_state.json` directly.

## Producer Internals

| Responsibility | Current implementation | Evidence |
| --- | --- | --- |
| Runtime path selection | The daemon uses the shared XDG helpers, including `paths::db_path()` for the unified SQLite file, falls back to `/run/user/$UID` for the JSON summary when needed, and shares that same runtime-dir fallback with the Quickshell consumer | `paths::db_path()` in `desktopctl/src/paths.rs` plus the runtime-summary path handling in `desktopctl/src/daemon/focus.rs` |
| SQLite initialization | WAL mode plus `CREATE TABLE IF NOT EXISTS` for `daily_totals`, `hourly_totals`, and `minute_totals`, all inside `desktopctl.db` | The database initialization path in `desktopctl/src/daemon/focus.rs` |
| Legacy data migration | On first access, the daemon imports rows from the legacy `focustime.db` when the shared focus tables are empty and then prints a cleanup hint | The legacy `focustime.db` import path in `desktopctl/src/daemon/focus.rs` |
| Per-second accumulation | One transaction increments the current class or `__locked__` in all three tables once per second | The per-second transaction loop in `desktopctl/src/daemon/focus.rs` |
| Retention | At the first tick of each new local day, the daemon deletes `minute_totals` rows older than 90 days and leaves `daily_totals` and `hourly_totals` untouched | The local-day rollover cleanup path in `desktopctl/src/daemon/focus.rs` |
| Summary building | The daemon computes today's totals, yesterday, the Monday-Sunday week, the current-month heatmap, and today's app list from SQLite; aggregate queries now exclude `__locked__`, `Desktop`, and `Quickshell`, and the root summary carries `last_updated` | The summary-query and JSON-shaping logic in `desktopctl/src/daemon/focus.rs` |
| JSON output | The summary is serialized to Python-compatible JSON and atomically renamed into place via `focustime_state.tmp` | The atomic `focustime_state.tmp` write path in `desktopctl/src/daemon/focus.rs` |
| Lock detection | `pgrep -x hyprlock` still defines the locked state | The `pgrep -x hyprlock` probe in `desktopctl/src/daemon/focus.rs` |
| Focus updates | The daemon seeds from `hyprctl activewindow -j` at startup and again after each successful socket reconnect, re-resolves the socket path on every reconnect loop, and then listens for `activewindow>>` lines on Hyprland's `.socket2.sock` with a fixed reconnect sleep | The Hyprland socket helpers in `desktopctl/src/hypr.rs` plus the reconnect/seed loop in `desktopctl/src/daemon/focus.rs` |
| App metadata cache | `.desktop` files are indexed by `StartupWMClass` and file stem under XDG data dirs plus the common Nix application directories | The desktop-entry indexer in `desktopctl/src/daemon/focus.rs` |

## Consumer Internals

| Concern | Current implementation | Evidence |
| --- | --- | --- |
| Read path | A `Process` runs `bash -c 'state_root="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"; state_path="$state_root/focustime_state.json"; [ -f "$state_path" ] || exit 3; cat -- "$state_path"'` | The `stateProc.command` definition in `config/quickshell/popups/settings/SettingsFocusTimePane.qml` |
| Parse behavior | Exit code `3` maps to "The focus time daemon is not running"; other read failures or parse failures map to "Unable to read focus time data"; parsed summaries older than 5 seconds map to "Focus daemon has not updated recently"; charts remain hidden until the first fresh payload primes `chartVisualsReady` | `emptyStateMessage`, `stateProc.onExited`, and the `chartVisualsReady` gate in `config/quickshell/popups/settings/SettingsFocusTimePane.qml` |
| Poll cadence | The pane triggers an immediate read on mount, then polls every 3000 ms while idle | `Component.onCompleted` plus the 3000 ms `Timer` in `config/quickshell/popups/settings/SettingsFocusTimePane.qml` |
| Derived fields | The pane projects fresh JSON into totals, current app, app list, week series, month heatmap, and week range; `last_updated` is consumed only by the freshness gate; chart cell sizes and label sizes now scale from theme metrics instead of fixed pixel constants | The top-level derived properties and chart layouts in `config/quickshell/popups/settings/SettingsFocusTimePane.qml` |

## External Runtime Surfaces

| Path or command | Owner | Current usage | Evidence |
| --- | --- | --- | --- |
| `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` and `/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` | Hyprland | Focus tracker prefers the runtime socket, falls back to `/tmp/hypr`, and can rediscover the newest available socket during reconnects | The socket-resolution helpers in `desktopctl/src/hypr.rs` plus the reconnect loop in `desktopctl/src/daemon/focus.rs` |
| `hyprctl activewindow -j` | Hyprland CLI | Used for the startup snapshot of the current focused class and for each successful socket reconnect reseed | The `hyprctl` snapshot helper in `desktopctl/src/hypr.rs` and the reseed path in `desktopctl/src/daemon/focus.rs` |
| `pgrep -x hyprlock` | Process table / `hyprlock` | Used as the lock-state probe every second | The lock-state probe in `desktopctl/src/daemon/focus.rs` |
| `XDG_DATA_HOME/applications` and `XDG_DATA_DIRS/*/applications` | Desktop-entry providers | Used for app-name and icon lookup | The desktop-entry indexer in `desktopctl/src/daemon/focus.rs` |
| `/run/current-system/sw/share/applications` and `~/.nix-profile/share/applications` | Nix package profiles | Appended when absent from `XDG_DATA_DIRS` | The Nix-profile fallback path handling in `desktopctl/src/daemon/focus.rs` |
