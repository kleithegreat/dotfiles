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
   `$XDG_DATA_HOME/focustime/focustime.db` and
   `$XDG_RUNTIME_DIR/focustime_state.json`.
5. `SettingsFocusTimePane.qml` still polls the JSON summary every 3 seconds and
   does not talk to SQLite or the daemon socket directly.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `home/default.nix` | Installs `desktopctl` and the Hyprland config fragments that source `autostart.conf` | `home/default.nix:33-45`, `home/default.nix:182-199` |
| `config/hypr/autostart.conf` | Starts `desktopctl daemon` during session startup | `config/hypr/autostart.conf:6-8` |
| `desktopctl/src/daemon/mod.rs` | Builds the tokio runtime and starts focus, solar, and socket subsystems together | `desktopctl/src/daemon/mod.rs:19-100` |
| `desktopctl/src/daemon/focus.rs` | Implements the full focus producer: Hyprland socket listener, SQLite writes, desktop-file cache, summary building, and atomic JSON replacement | `desktopctl/src/daemon/focus.rs:20-145`, `desktopctl/src/daemon/focus.rs:148-418`, `desktopctl/src/daemon/focus.rs:455-768` |
| `config/quickshell/popups/SettingsPopup.qml` | Still mounts the focus-time pane as settings category `5` | `config/quickshell/popups/SettingsPopup.qml:787-842` |
| `config/quickshell/popups/settings/SettingsFocusTimePane.qml` | Polls the JSON summary, derives UI state, and renders totals, charts, and app breakdowns | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:16-72`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:113-220` |

No other repo file reads `focustime_state.json` directly.

## Producer Internals

| Responsibility | Current implementation | Evidence |
| --- | --- | --- |
| Runtime path selection | The daemon uses the shared XDG helpers and falls back to `~/.local/share` and `/run/user/$UID` when needed | `desktopctl/src/paths.rs:20-54`, `desktopctl/src/daemon/focus.rs:70-74`, `desktopctl/src/daemon/focus.rs:335-342` |
| SQLite initialization | WAL mode plus `CREATE TABLE IF NOT EXISTS` for `daily_totals`, `hourly_totals`, and `minute_totals` | `desktopctl/src/daemon/focus.rs:70-101` |
| Per-second accumulation | One transaction increments the current class or `__locked__` in all three tables once per second | `desktopctl/src/daemon/focus.rs:34-67`, `desktopctl/src/daemon/focus.rs:104-131` |
| Summary building | The daemon computes today's totals, yesterday, the Monday-Sunday week, the current-month heatmap, and today's app list from SQLite | `desktopctl/src/daemon/focus.rs:148-333` |
| JSON output | The summary is serialized to Python-compatible JSON and atomically renamed into place via `focustime_state.tmp` | `desktopctl/src/daemon/focus.rs:134-145`, `desktopctl/src/daemon/focus.rs:571-768` |
| Lock detection | `pgrep -x hyprlock` still defines the locked state | `desktopctl/src/daemon/focus.rs:345-350` |
| Focus updates | The daemon seeds from `hyprctl activewindow -j` and then listens for `activewindow>>` lines on Hyprland's `.socket2.sock` with a fixed reconnect sleep | `desktopctl/src/hypr.rs:21-25`, `desktopctl/src/hypr.rs:63-76`, `desktopctl/src/daemon/focus.rs:353-418` |
| App metadata cache | `.desktop` files are indexed by `StartupWMClass` and file stem under XDG data dirs plus the common Nix application directories | `desktopctl/src/daemon/focus.rs:455-568` |

## Consumer Internals

| Concern | Current implementation | Evidence |
| --- | --- | --- |
| Read path | A `Process` still runs `bash -c 'cat -- "$XDG_RUNTIME_DIR/focustime_state.json" 2>/dev/null || true'` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:44-47` |
| Parse behavior | Non-empty stdout is parsed with `JSON.parse`; parse failure or empty stdout clears `hasData` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:50-64` |
| Poll cadence | The pane triggers an immediate read on mount, then polls every 3000 ms while idle | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:67-72` |
| Derived fields | The pane projects the JSON into totals, current app, app list, week series, month heatmap, and week range | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:16-40` |

## External Runtime Surfaces

| Path or command | Owner | Current usage | Evidence |
| --- | --- | --- | --- |
| `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` | Hyprland | Focus tracker reads `activewindow>>` lines here | `desktopctl/src/hypr.rs:63-76`, `desktopctl/src/daemon/focus.rs:365-418` |
| `hyprctl activewindow -j` | Hyprland CLI | Used for the startup snapshot of the current focused class | `desktopctl/src/hypr.rs:21-25`, `desktopctl/src/daemon/focus.rs:353-362` |
| `pgrep -x hyprlock` | Process table / `hyprlock` | Used as the lock-state probe every second | `desktopctl/src/daemon/focus.rs:345-350` |
| `XDG_DATA_HOME/applications` and `XDG_DATA_DIRS/*/applications` | Desktop-entry providers | Used for app-name and icon lookup | `desktopctl/src/daemon/focus.rs:455-568` |
| `/run/current-system/sw/share/applications` and `~/.nix-profile/share/applications` | Nix package profiles | Appended when absent from `XDG_DATA_DIRS` | `desktopctl/src/daemon/focus.rs:474-477` |
