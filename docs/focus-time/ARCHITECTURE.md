# Focus Time Architecture

## Scope

Current implementation map for the focus-time subsystem as of 2026-04-03.

## Runtime Topology

1. Home Manager installs `desktopctl` into the user environment through
   `home/default.nix:33-45`.
2. Hyprland starts `desktopctl daemon` once per session through
   `config/hypr/autostart.conf:6-8`.
3. `desktopctl/src/daemon/mod.rs:19-100` starts the focus tracker alongside the
   solar scheduler and socket server under one tokio runtime.
4. The focus tracker owns both runtime artifacts:
   `$XDG_DATA_HOME/desktopctl/desktopctl.db` and
   `$XDG_RUNTIME_DIR/focustime_state.json`.
5. `SettingsFocusTimePane.qml` still polls the JSON summary every 3 seconds,
   derives missing/stale/parse-error state locally, and does not talk to SQLite
   or the daemon socket directly.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `home/default.nix` | Installs `desktopctl` and the Hyprland config fragments that source `autostart.conf` | `home/default.nix:33-45`, `home/default.nix:182-199` |
| `config/hypr/autostart.conf` | Starts `desktopctl daemon` during session startup | `config/hypr/autostart.conf:6-8` |
| `desktopctl/src/daemon/mod.rs` | Builds the tokio runtime and starts focus, solar, and socket subsystems together | `desktopctl/src/daemon/mod.rs:19-100` |
| `desktopctl/src/daemon/focus.rs` | Implements the full focus producer: shared-DB initialization, legacy focus-data migration, per-second accumulation, daily minute-table retention, reconnect seeding, desktop-file cache, summary building, and atomic JSON replacement | `desktopctl/src/daemon/focus.rs:20-577`, `desktopctl/src/daemon/focus.rs:617-800` |
| `config/quickshell/popups/SettingsPopup.qml` | Still mounts the focus-time pane as settings category `5` | `config/quickshell/popups/SettingsPopup.qml:787-842` |
| `config/quickshell/popups/settings/SettingsFocusTimePane.qml` | Polls the JSON summary, classifies missing/stale/parse failures, and renders totals, charts, and app breakdowns only for fresh data | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:16-90`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:132-418` |

No other repo file reads `focustime_state.json` directly.

## Producer Internals

| Responsibility | Current implementation | Evidence |
| --- | --- | --- |
| Runtime path selection | The daemon uses the shared XDG helpers, including `paths::db_path()` for the unified SQLite file, and still falls back to `/run/user/$UID` for the JSON summary when needed | `desktopctl/src/paths.rs:29-60`, `desktopctl/src/daemon/focus.rs:77-110`, `desktopctl/src/daemon/focus.rs:487-494` |
| SQLite initialization | WAL mode plus `CREATE TABLE IF NOT EXISTS` for `daily_totals`, `hourly_totals`, and `minute_totals`, all inside `desktopctl.db` | `desktopctl/src/daemon/focus.rs:77-103` |
| Legacy data migration | On first access, the daemon imports rows from the legacy `focustime.db` when the shared focus tables are empty and then prints a cleanup hint | `desktopctl/src/daemon/focus.rs:131-243` |
| Per-second accumulation | One transaction increments the current class or `__locked__` in all three tables once per second | `desktopctl/src/daemon/focus.rs:20-63`, `desktopctl/src/daemon/focus.rs:245-272` |
| Retention | At the first tick of each new local day, the daemon deletes `minute_totals` rows older than 90 days and leaves `daily_totals` and `hourly_totals` untouched | `desktopctl/src/daemon/focus.rs:44-48`, `desktopctl/src/daemon/focus.rs:505-508` |
| Summary building | The daemon computes today's totals, yesterday, the Monday-Sunday week, the current-month heatmap, and today's app list from SQLite; aggregate queries now exclude `__locked__`, `Desktop`, and `Quickshell`, and the root summary carries `last_updated` | `desktopctl/src/daemon/focus.rs:290-485`, `desktopctl/src/daemon/focus.rs:729-800` |
| JSON output | The summary is serialized to Python-compatible JSON and atomically renamed into place via `focustime_state.tmp` | `desktopctl/src/daemon/focus.rs:275-287`, `desktopctl/src/daemon/focus.rs:742-800` |
| Lock detection | `pgrep -x hyprlock` still defines the locked state | `desktopctl/src/daemon/focus.rs:497-503` |
| Focus updates | The daemon seeds from `hyprctl activewindow -j` at startup and again after each successful socket reconnect, then listens for `activewindow>>` lines on Hyprland's `.socket2.sock` with a fixed reconnect sleep | `desktopctl/src/hypr.rs:21-25`, `desktopctl/src/hypr.rs:63-76`, `desktopctl/src/daemon/focus.rs:20-28`, `desktopctl/src/daemon/focus.rs:523-577` |
| App metadata cache | `.desktop` files are indexed by `StartupWMClass` and file stem under XDG data dirs plus the common Nix application directories | `desktopctl/src/daemon/focus.rs:617-727` |

## Consumer Internals

| Concern | Current implementation | Evidence |
| --- | --- | --- |
| Read path | A `Process` runs `bash -c 'state_path="$XDG_RUNTIME_DIR/focustime_state.json"; [ -f "$state_path" ] || exit 3; cat -- "$state_path"'` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:52-54` |
| Parse behavior | Exit code `3` maps to "daemon is not running"; other read failures or parse failures map to "unable to read"; parsed summaries older than 10 seconds map to "daemon is not responding" and do not render charts | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:28-34`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:57-83`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:132-157` |
| Poll cadence | The pane triggers an immediate read on mount, then polls every 3000 ms while idle | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:86-90` |
| Derived fields | The pane projects fresh JSON into totals, current app, app list, week series, month heatmap, and week range; `last_updated` is consumed only by the freshness gate | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:16-48`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:160-418` |

## External Runtime Surfaces

| Path or command | Owner | Current usage | Evidence |
| --- | --- | --- | --- |
| `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` | Hyprland | Focus tracker reads `activewindow>>` lines here | `desktopctl/src/hypr.rs:63-76`, `desktopctl/src/daemon/focus.rs:523-571` |
| `hyprctl activewindow -j` | Hyprland CLI | Used for the startup snapshot of the current focused class and for each successful socket reconnect reseed | `desktopctl/src/hypr.rs:21-25`, `desktopctl/src/daemon/focus.rs:20-24`, `desktopctl/src/daemon/focus.rs:529-530` |
| `pgrep -x hyprlock` | Process table / `hyprlock` | Used as the lock-state probe every second | `desktopctl/src/daemon/focus.rs:497-503` |
| `XDG_DATA_HOME/applications` and `XDG_DATA_DIRS/*/applications` | Desktop-entry providers | Used for app-name and icon lookup | `desktopctl/src/daemon/focus.rs:617-727` |
| `/run/current-system/sw/share/applications` and `~/.nix-profile/share/applications` | Nix package profiles | Appended when absent from `XDG_DATA_DIRS` | `desktopctl/src/daemon/focus.rs:632-639` |
