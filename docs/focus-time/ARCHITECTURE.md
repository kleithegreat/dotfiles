# Focus Time Architecture

## Scope

Current implementation map for the focus-time subsystem as of 2026-06-10.

For package installation and Hyprland session startup ownership, see
`docs/nix/ARCHITECTURE.md` and `docs/hyprland/ARCHITECTURE.md`.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `config/hypr/autostart.conf` | Starts `desktopctl daemon` during session startup | The `exec-once = $cleanSessionEnv desktopctl daemon` entry |
| `desktopctl/src/daemon/mod.rs` | Builds the tokio runtime and starts focus, solar, and socket subsystems together | The daemon `run()` / `run_async()` bootstrap |
| `desktopctl/src/daemon/focus.rs` | Implements the full focus producer: shared-DB initialization, legacy focus-data migration, per-second accumulation, empty-class reseeding, daily minute-table retention, reconnect seeding, socket re-resolution, desktop-file cache, summary building, and atomic JSON replacement | The focus tracker implementation and JSON summary writer in `desktopctl/src/daemon/focus.rs` |
| `config/quickshell/popups/SettingsPopup.qml` | Mounts the focus-time pane as the "Screen Time" settings category, after the Notifications pane | The `categoryNames` list and settings-detail loader wiring in `config/quickshell/popups/SettingsPopup.qml` |
| `config/quickshell/popups/settings/SettingsFocusTimePane.qml` | Polls the JSON summary, classifies missing/stale/parse failures, keeps the previous ready payload mounted across consecutive successful polls, holds charts behind a first-fresh-payload gate, and renders totals, charts, and app breakdowns only for fresh data. The pane tears down to the empty/stale state as soon as a poll is missing, stale, or unparseable | The pane state machine and chart rendering in `config/quickshell/popups/settings/SettingsFocusTimePane.qml` |

No other repo file reads `focustime_state.json` directly.

## Producer Internals

| Responsibility | Current implementation | Evidence |
| --- | --- | --- |
| Runtime path selection | The daemon uses the shared XDG helpers, including `paths::db_path()` for the unified SQLite file, falls back to `/run/user/$UID` for the JSON summary when needed, and shares that same runtime-dir fallback with the Quickshell consumer | `paths::db_path()` in `desktopctl/src/paths.rs` plus the runtime-summary path handling in `desktopctl/src/daemon/focus.rs` |
| SQLite initialization | WAL mode plus `CREATE TABLE IF NOT EXISTS` for `daily_totals`, `hourly_totals`, and `minute_totals`, all inside `desktopctl.db` | The database initialization path in `desktopctl/src/daemon/focus.rs` |
| Legacy data migration | On first access, the daemon imports rows from the legacy `focustime.db` when the shared focus tables are empty and then prints a cleanup hint | The legacy `focustime.db` import path in `desktopctl/src/daemon/focus.rs` |
| Per-second accumulation | One transaction increments the current class or `__locked__` in all three tables once per second | The per-second transaction loop in `desktopctl/src/daemon/focus.rs` |
| Retention | At the first tick of each new local day, the daemon deletes `minute_totals` rows older than 90 days and leaves `daily_totals` and `hourly_totals` untouched | The local-day rollover cleanup path in `desktopctl/src/daemon/focus.rs` |
| Summary building | The daemon computes today's totals, yesterday, the Monday-Sunday week, the current-month heatmap, and today's app list from SQLite; aggregate queries exclude `__locked__`, `Desktop`, `Quickshell`, and empty-string classes, and the root summary carries `last_updated` | The summary-query and JSON-shaping logic in `desktopctl/src/daemon/focus.rs` |
| JSON output | The summary types derive `serde::Serialize` (with a custom tenths-based `Percent` serializer), render through the shared Python-compatible `theme::json` formatter, and are atomically renamed into place via `focustime_state.tmp` | The `Summary` / `AppEntry` / `Percent` serialization and atomic `focustime_state.tmp` write path in `desktopctl/src/daemon/focus.rs` |
| Lock detection | `pgrep -x hyprlock` still defines the locked state | The `pgrep -x hyprlock` probe in `desktopctl/src/daemon/focus.rs` |
| Focus updates | The daemon seeds from `hyprctl activewindow -j` at startup, retries that seed on unlocked ticks when the shared class is still empty, seeds again after each successful socket reconnect, re-resolves the socket path on every reconnect loop, and then listens for `activewindow>>` lines on Hyprland's `.socket2.sock` with a fixed reconnect sleep | The Hyprland socket helpers in `desktopctl/src/hypr.rs` plus the reconnect/seed loop in `desktopctl/src/daemon/focus.rs` |
| App metadata cache | `.desktop` files are indexed once at focus-tracker startup by `StartupWMClass` and file stem under XDG data dirs plus the common Nix application directories; the index is never refreshed while the daemon runs | The desktop-entry indexer in `desktopctl/src/daemon/focus.rs` |

## Consumer Internals

| Concern | Current implementation | Evidence |
| --- | --- | --- |
| Read path and parse behavior | Implements the read contract in `docs/focus-time/SPEC.md` (Quickshell Read Contract): the exact read command, poll cadence, exit-code mapping, error messages, and staleness window live there. Successful refreshes swap `stateData` only after the new payload has been parsed, so charts and the app list stay mounted across consecutive successful polls; a missing, stale, or unparseable poll tears the pane down to the empty-state message immediately. Charts remain hidden until the first fresh payload primes `chartVisualsReady` | `stateProc`, `emptyStateMessage`, and the `chartVisualsReady` gate in `config/quickshell/popups/settings/SettingsFocusTimePane.qml` |
| Derived fields | The pane projects fresh JSON into totals, current app, app list, week series, month heatmap, and week range; `last_updated` is consumed only by the freshness gate; chart cell sizes and label sizes scale from theme metrics instead of fixed pixel constants | The top-level derived properties and chart layouts in `config/quickshell/popups/settings/SettingsFocusTimePane.qml` |

## External Runtime Surfaces

| Path or command | Owner | Current usage | Evidence |
| --- | --- | --- | --- |
| `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` and `/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` | Hyprland | Focus tracker prefers the runtime socket, falls back to `/tmp/hypr`, and can rediscover the newest available socket during reconnects | The socket-resolution helpers in `desktopctl/src/hypr.rs` plus the reconnect loop in `desktopctl/src/daemon/focus.rs` |
| `hyprctl activewindow -j` | Hyprland CLI | Used for the startup snapshot of the current focused class, unlocked empty-class repair ticks, and each successful socket reconnect reseed | The `hyprctl` snapshot helper in `desktopctl/src/hypr.rs` and the reseed path in `desktopctl/src/daemon/focus.rs` |
| `pgrep -x hyprlock` | Process table / `hyprlock` | Used as the lock-state probe every second | The lock-state probe in `desktopctl/src/daemon/focus.rs` |
| `XDG_DATA_HOME/applications` and `XDG_DATA_DIRS/*/applications` | Desktop-entry providers | Used for app-name and icon lookup | The desktop-entry indexer in `desktopctl/src/daemon/focus.rs` |
| `/run/current-system/sw/share/applications` and `~/.nix-profile/share/applications` | Nix package profiles | Appended when absent from `XDG_DATA_DIRS` | The Nix-profile fallback path handling in `desktopctl/src/daemon/focus.rs` |
