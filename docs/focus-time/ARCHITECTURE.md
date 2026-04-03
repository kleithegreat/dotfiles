# Focus Time Architecture

## Scope

Current implementation map for the focus-time subsystem as of 2026-04-02.

## Runtime Topology

1. Home Manager installs the daemon script into `~/.local/bin/` and deploys the
   Hyprland config fragments that start it.
2. Hyprland reads `~/.config/hypr/hyprland.conf`, which sources
   `~/.config/hypr/autostart.conf`.
3. `autostart.conf` launches `~/.local/bin/focus-daemon.py` once per Hyprland
   session.
4. The daemon snapshots the current focused class with `hyprctl`, starts a
   background thread that listens to Hyprland's Unix socket, then runs a
   one-second accumulator loop.
5. Each loop iteration optionally writes one second into SQLite and always
   rewrites the JSON summary file.
6. `SettingsPopup.qml` selects `SettingsFocusTimePane.qml` for category index
   `5`; that pane polls the JSON file every three seconds and renders the UI
   directly from the parsed object.

## File Map

| Path | Current role | Evidence |
| --- | --- | --- |
| `home/default.nix` | Installs `config/hypr/*.conf` into `~/.config/hypr/` and installs the daemon as `~/.local/bin/focus-daemon.py` | `home/default.nix:184-186`, `home/default.nix:257-273` |
| `config/hypr/hyprland.conf` | Sources `autostart.conf` as part of the compositor include graph | `config/hypr/hyprland.conf:4-14` |
| `config/hypr/autostart.conf` | Starts the focus daemon with `exec-once = ~/.local/bin/focus-daemon.py` | `config/hypr/autostart.conf:21-22` |
| `scripts/focus-daemon.py` | Defines runtime paths, SQLite schema, summary generation, Hyprland socket listener, and the main loop | `scripts/focus-daemon.py:27-35`, `scripts/focus-daemon.py:113-138`, `scripts/focus-daemon.py:168-266`, `scripts/focus-daemon.py:279-396` |
| `config/quickshell/popups/SettingsPopup.qml` | Mounts the focus-time pane as settings category `5` | `config/quickshell/popups/SettingsPopup.qml:787-842` |
| `config/quickshell/popups/settings/SettingsFocusTimePane.qml` | Polls the JSON summary, parses it, derives UI-local state, and renders totals/charts/app breakdowns | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:16-72`, `config/quickshell/popups/settings/SettingsFocusTimePane.qml:141-400` |

No other repo file currently reads `focustime_state.json` directly.

## Daemon Internals

| Responsibility | Current implementation | Evidence |
| --- | --- | --- |
| Runtime path selection | `DATA_DIR`, `DB_PATH`, and `STATE_PATH` come from `XDG_DATA_HOME` / `XDG_RUNTIME_DIR` with user-home fallbacks | `scripts/focus-daemon.py:27-35` |
| App metadata cache | Desktop files are scanned lazily and cached by lowercase `StartupWMClass` and desktop-file stem | `scripts/focus-daemon.py:43-109` |
| SQLite initialization | Opens one connection, enables WAL, and creates `daily_totals`, `hourly_totals`, and `minute_totals` if missing | `scripts/focus-daemon.py:113-139` |
| Per-second accumulation | One transaction UPSERTs the same second into all three tables | `scripts/focus-daemon.py:142-164` |
| Summary building | Computes today's totals, yesterday, Monday-Sunday week totals, current-month heatmap cells, and today's app breakdown | `scripts/focus-daemon.py:168-258` |
| State-file write | Serializes JSON to `STATE_PATH.with_suffix(".tmp")`, then renames over the live file | `scripts/focus-daemon.py:261-266` |
| Lock detection | Treats `pgrep -x hyprlock` success as the locked state and writes `__locked__` during those ticks | `scripts/focus-daemon.py:271-275`, `scripts/focus-daemon.py:369-376` |
| Focus updates | Seeds `_class` with `hyprctl activewindow -j`, then updates it from `activewindow>>` events on `.socket2.sock` | `scripts/focus-daemon.py:287-297`, `scripts/focus-daemon.py:318-349`, `scripts/focus-daemon.py:352-380` |

## Consumer Internals

| Concern | Current implementation | Evidence |
| --- | --- | --- |
| Read path | A `Process` runs `bash -c 'cat -- \"$XDG_RUNTIME_DIR/focustime_state.json\" 2>/dev/null || true'` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:44-47` |
| Parse behavior | Non-empty stdout is parsed with `JSON.parse`; parse failure clears `hasData` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:49-64` |
| Poll cadence | `Component.onCompleted` triggers an immediate read; a `Timer` triggers every 3000 ms after that | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:67-72` |
| Derived fields | The pane projects `stateData` into `totalSeconds`, `yesterdaySeconds`, `averageSeconds`, `currentApp`, `apps`, `weekData`, `monthData`, and `weekRange` | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:16-40` |
| Rendering | The pane shows an empty state, headline totals, weekly bar chart, monthly heatmap, and per-app progress bars | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:113-399` |

## External Runtime Surfaces

| Path or command | Owner | Current usage | Evidence |
| --- | --- | --- | --- |
| `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock` | Hyprland | Listener thread reads `activewindow>>` lines to update the current class | `scripts/focus-daemon.py:279-285`, `scripts/focus-daemon.py:318-349` |
| `hyprctl activewindow -j` | Hyprland CLI | Startup-time snapshot of the currently focused class | `scripts/focus-daemon.py:287-297`, `scripts/focus-daemon.py:353` |
| `pgrep -x hyprlock` | Process table / `hyprlock` | Lock-state probe each second | `scripts/focus-daemon.py:271-275`, `scripts/focus-daemon.py:367-373` |
| `XDG_DATA_HOME/applications` and `XDG_DATA_DIRS/*/applications` | Desktop-entry providers | Name/icon lookup for app rows and current app label | `scripts/focus-daemon.py:47-109` |
| `/run/current-system/sw/share/applications` and `~/.nix-profile/share/applications` | Nix package profiles | Extra desktop-entry lookup roots appended when absent from `XDG_DATA_DIRS` | `scripts/focus-daemon.py:57-60` |

## Data Flow Notes

- The daemon keeps one SQLite connection open for the full process lifetime.
- The listener thread and the main loop share only the current window class via a
  `threading.Lock`.
- The JSON summary is rebuilt from SQLite every tick rather than incrementally
  patched in memory.
- The Quickshell pane has no shared service wrapper; the producer/consumer
  boundary is the JSON file itself.
