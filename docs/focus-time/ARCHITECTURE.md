# Focus Time Architecture

## Scope

Current implementation map for the focus-time subsystem as of 2026-04-03.

## Runtime Topology

1. Home Manager still installs `~/.local/bin/focus-daemon.py` and the Hyprland
   config fragments that launch it at session start.
2. Hyprland still sources `autostart.conf`, and `autostart.conf` still launches
   the Python daemon once per session.
3. The repo now also contains a Rust port behind `desktopctl daemon`; it is not
   wired into Home Manager or Hyprland yet, but it targets the same SQLite and
   JSON runtime contract.
4. Both producer implementations use the same Hyprland event socket, SQLite
   path, and `focustime_state.json` file shape.
5. `SettingsPopup.qml` still selects `SettingsFocusTimePane.qml` for category
   index `5`, and that pane still polls the JSON file every three seconds.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `home/default.nix` | Still installs `config/hypr/*.conf` into `~/.config/hypr/` and installs the legacy daemon as `~/.local/bin/focus-daemon.py` | `home/default.nix:184-186`, `home/default.nix:257-273` |
| `config/hypr/hyprland.conf` | Still sources `autostart.conf` as part of the compositor include graph | `config/hypr/hyprland.conf:4-14` |
| `config/hypr/autostart.conf` | Still starts the Python focus daemon with `exec-once = ~/.local/bin/focus-daemon.py` | `config/hypr/autostart.conf:21-22` |
| `scripts/focus-daemon.py` | Remains the session-wired reference implementation for the SQLite schema, lock detection, desktop-entry lookup, and JSON contract | `scripts/focus-daemon.py:27-35`, `scripts/focus-daemon.py:113-266`, `scripts/focus-daemon.py:279-396` |
| `desktopctl/src/main.rs` | Adds a parallel Rust entry point for the subsystem via `desktopctl daemon` | `desktopctl/src/main.rs:27-42`, `desktopctl/src/main.rs:206-217` |
| `desktopctl/src/daemon/mod.rs` | Builds the tokio runtime and starts the Rust focus tracker alongside the solar scheduler and placeholder socket server | `desktopctl/src/daemon/mod.rs:19-100` |
| `desktopctl/src/daemon/focus.rs` | Ports the focus producer: Hyprland socket listener, SQLite writes, desktop-file cache, Python-compatible JSON serialization, and atomic state-file replacement | `desktopctl/src/daemon/focus.rs:20-145`, `desktopctl/src/daemon/focus.rs:148-418`, `desktopctl/src/daemon/focus.rs:422-773` |
| `config/quickshell/popups/SettingsPopup.qml` | Still mounts the focus-time pane as settings category `5` | `config/quickshell/popups/SettingsPopup.qml:787-842` |
| `config/quickshell/popups/settings/SettingsFocusTimePane.qml` | Still polls the JSON summary, parses it, derives UI-local state, and renders totals, charts, and app breakdowns | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:16-72`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:141-400` |

No other repo file currently reads `focustime_state.json` directly.

## Producer Internals

| Responsibility | Current implementation | Evidence |
| --- | --- | --- |
| Runtime path selection | The Rust port uses the shared XDG helpers to resolve the same data and runtime fallbacks as the Python daemon | `desktopctl/src/paths.rs:33-58`, `desktopctl/src/daemon/focus.rs:70-74`, `desktopctl/src/daemon/focus.rs:337-345` |
| App metadata cache | The Rust port scans `.desktop` files under XDG data dirs, `/run/current-system/sw/share`, and `~/.nix-profile/share`, indexing both `StartupWMClass` and file stem in lowercase | `desktopctl/src/daemon/focus.rs:455-568` |
| SQLite initialization | The Rust port enables WAL and creates `daily_totals`, `hourly_totals`, and `minute_totals` if they are missing | `desktopctl/src/daemon/focus.rs:70-101` |
| Per-second accumulation | One transaction increments the same second into all three tables for the current class or `__locked__` | `desktopctl/src/daemon/focus.rs:104-131` |
| Summary building | The Rust port computes today's totals, yesterday, Monday-Sunday week totals, current-month heatmap cells, and today's app breakdown from SQLite each tick | `desktopctl/src/daemon/focus.rs:148-334` |
| JSON output | The Rust port emits Python-style JSON key ordering, spacing, and string escaping before renaming `focustime_state.tmp` over `focustime_state.json` | `desktopctl/src/daemon/focus.rs:134-145`, `desktopctl/src/daemon/focus.rs:571-773` |
| Lock detection | The Rust port still treats `pgrep -x hyprlock` success as the locked state | `desktopctl/src/daemon/focus.rs:347-353` |
| Focus updates | The Rust port still seeds the class with `hyprctl activewindow -j` and updates it from `activewindow>>` lines on `.socket2.sock` with a fixed 2-second reconnect sleep | `desktopctl/src/daemon/focus.rs:20-30`, `desktopctl/src/daemon/focus.rs:355-418` |

## Consumer Internals

| Concern | Current implementation | Evidence |
| --- | --- | --- |
| Read path | A `Process` still runs `bash -c 'cat -- \"$XDG_RUNTIME_DIR/focustime_state.json\" 2>/dev/null || true'` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:44-47` |
| Parse behavior | Non-empty stdout is still parsed with `JSON.parse`; parse failure still clears `hasData` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:49-64` |
| Poll cadence | `Component.onCompleted` still triggers an immediate read, and a `Timer` still triggers every 3000 ms after that | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:67-72` |
| Derived fields | The pane still projects `stateData` into `totalSeconds`, `yesterdaySeconds`, `averageSeconds`, `currentApp`, `apps`, `weekData`, `monthData`, and `weekRange` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:16-40` |
| Rendering | The pane still shows an empty state, headline totals, weekly bar chart, monthly heatmap, and per-app progress bars | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:113-399` |

## External Runtime Surfaces

| Path or command | Owner | Current usage | Evidence |
| --- | --- | --- | --- |
| `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` | Hyprland | Both the Python daemon and the Rust port read `activewindow>>` lines here to track the focused class | `scripts/focus-daemon.py:279-285`, `desktopctl/src/hypr.rs:76-88`, `desktopctl/src/daemon/focus.rs:367-418` |
| `hyprctl activewindow -j` | Hyprland CLI | Both producer implementations use it for the startup-time snapshot of the currently focused class | `scripts/focus-daemon.py:287-297`, `desktopctl/src/hypr.rs:28-31`, `desktopctl/src/daemon/focus.rs:355-365` |
| `pgrep -x hyprlock` | Process table / `hyprlock` | Both producer implementations use it as the lock-state probe each second | `scripts/focus-daemon.py:271-275`, `desktopctl/src/daemon/focus.rs:347-353` |
| `XDG_DATA_HOME/applications` and `XDG_DATA_DIRS/*/applications` | Desktop-entry providers | Both producers use them for app-name and icon lookup | `scripts/focus-daemon.py:47-109`, `desktopctl/src/daemon/focus.rs:455-568` |
| `/run/current-system/sw/share/applications` and `~/.nix-profile/share/applications` | Nix package profiles | Both producers append these when they are absent from `XDG_DATA_DIRS` | `scripts/focus-daemon.py:57-60`, `desktopctl/src/daemon/focus.rs:474-477` |

## Data Flow Notes

- The Rust port keeps one SQLite connection open for the full daemon lifetime,
  matching the Python daemon's one-connection model.
- The Rust port shares only the current window class between its socket thread
  and the one-second accumulator loop, preserving the same producer shape as the
  Python implementation.
- The producer/consumer boundary is still the JSON file itself; the Quickshell
  pane does not read SQLite or open the placeholder daemon socket.
- Session wiring still points at the Python daemon today, so the Rust port is
  available for manual use and follow-on integration work rather than being the
  default session producer yet.
