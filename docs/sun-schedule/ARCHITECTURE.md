# Sun Schedule Architecture

## Scope

Current implementation map for solar scheduling, timer creation, location
resolution, and cross-domain side effects as of 2026-04-02.

## Primary Implementation Surface

| Path | Current role | Evidence |
| --- | --- | --- |
| `home/default.nix` | Imports the `sun-schedule` module and installs `hyprsunset` plus `geoclue2-with-demo-agent` in the user environment. | `home/default.nix:7-12`, `home/default.nix:136-141` |
| `home/sun-schedule.nix` | Declares the recurring `sun-scheduler.service` and `sun-scheduler.timer` user units. | `home/sun-schedule.nix:4-19` |
| `scripts/sun-schedule` | Resolves coordinates, computes solar times, reconciles current state, and creates transient `sun-event-*` timers. | `scripts/sun-schedule:25-35`, `scripts/sun-schedule:40-75`, `scripts/sun-schedule:80-121`, `scripts/sun-schedule:126-170`, `scripts/sun-schedule:175-236` |
| `themes/apply-theme` | Handles `dark_hint` requests by loading state, coercing values, saving `themes/state.json`, and applying affected targets. | `themes/apply-theme:19-30`, `themes/apply-theme:228-256`, `themes/apply-theme:259-297` |
| `themes/lib/resolve.py` | Validates and rewrites `themes/state.json`. | `themes/lib/resolve.py:76-110` |
| `themes/lib/orchestrator.py` | Routes `dark_hint` to the `gtk` target and executes runtime hooks such as `on_apply()`. | `themes/lib/orchestrator.py:15-37`, `themes/lib/orchestrator.py:124-137`, `themes/lib/orchestrator.py:215-220` |
| `themes/lib/targets/gtk.py` | Writes GTK dconf keys derived from the resolved theme state. | `themes/lib/targets/gtk.py:18-43` |

## Neighbor And Competing Surfaces

| Path | Current role | Evidence |
| --- | --- | --- |
| `config/quickshell/DisplayService.qml` | Polls `hyprsunset`, starts it directly, stops it with `pkill`, and restarts it to apply temperature changes. | `config/quickshell/DisplayService.qml:39-137`, `config/quickshell/DisplayService.qml:197-285` |
| `config/quickshell/popups/SettingsPopup.qml` | Reads `themes/state.json`, runs `apply-theme set`, and runs `apply-theme preset` from the settings UI. | `config/quickshell/popups/SettingsPopup.qml:158-170`, `config/quickshell/popups/SettingsPopup.qml:647-654`, `config/quickshell/popups/SettingsPopup.qml:866-870` |
| `config/quickshell/popups/settings/SettingsPresetEditor.qml` | Allows presets to include and edit the `dark_hint` field. | `config/quickshell/popups/settings/SettingsPresetEditor.qml:396-485` |
| `config/quickshell/shell.qml` | Exposes a generic `theme.apply` IPC entry point that can invoke `apply-theme` with arbitrary arguments. | `config/quickshell/shell.qml:294-306` |
| `config/hypr/keybinds.conf` | Adds manual `hyprsunset` stop/start keybinds outside the scheduler and Quickshell. | `config/hypr/keybinds.conf:73-75` |
| `themes/lib/targets/quickshell.py` | Writes `~/.config/quickshell/GeneratedTheme.json` for shell colors and fonts. | `themes/lib/targets/quickshell.py:7-48` |
| `config/quickshell/Theme.qml` | Watches `GeneratedTheme.json`; this file is not part of the `dark_hint` path. | `config/quickshell/Theme.qml:8-27` |

## Unit Inventory

| Unit | Source | Current behavior |
| --- | --- | --- |
| `sun-scheduler.service` | `home/sun-schedule.nix` | Runs `python3 .../scripts/sun-schedule schedule` as a oneshot user service. |
| `sun-scheduler.timer` | `home/sun-schedule.nix` | Fires 30 seconds after startup and every 2 hours after the last successful run. |
| `sun-event-sunrise.timer` and `.service` | `scripts/sun-schedule` via `systemd-run --user` | Single next-shot sunrise event; created with `Persistent=true`. |
| `sun-event-sunset.timer` and `.service` | `scripts/sun-schedule` via `systemd-run --user` | Single next-shot sunset event; created with `Persistent=true`. |
| `sun-event-dark-on.timer` and `.service` | `scripts/sun-schedule` via `systemd-run --user` | Single next-shot 23:00 local event; created with `Persistent=true`. |

Notes:

- `cancel_timers()` stops the transient `*.timer` units before recreating them,
  but it does not explicitly stop the sibling transient services.
- `systemd-run --collect` makes the transient event units garbage-collectable
  after they finish.

## Runtime Flow

1. Home Manager imports `home/sun-schedule.nix` from `home/default.nix` and
   provides the runtime tools that the script expects on `PATH`.
2. `sun-scheduler.timer` starts `sun-scheduler.service`, which runs
   `scripts/sun-schedule schedule`.
3. `get_location()` first reads
   `$XDG_CACHE_HOME/sun-schedule/location.json` (or
   `~/.cache/sun-schedule/location.json`), then tries `where-am-i`, then falls
   back to `30.6280, -96.3344`. The cache is written only after a fully parsed
   GeoClue result. See `scripts/sun-schedule:40-75`.
4. `sun_times()` computes timezone-aware sunrise and sunset for today and
   tomorrow, then `cmd_schedule()` derives the current booleans and the next
   event timestamps. See `scripts/sun-schedule:80-121` and
   `scripts/sun-schedule:175-220`.
5. The scheduler immediately reconciles the current state:
   `start_hyprsunset()` uses `hyprctl dispatch exec`, `stop_hyprsunset()` uses
   `pkill`, and `set_dark_hint()` shells out to `themes/apply-theme set
   dark_hint ...`. See `scripts/sun-schedule:126-149`,
   `scripts/sun-schedule:193-201`.
6. `apply-theme set dark_hint ...` loads `themes/state.json`, writes the new
   value back through `save_state()`, then asks the orchestrator for affected
   targets. The dependency map routes `dark_hint` only to `gtk`, so the runtime
   side effect is a GTK dconf update rather than a Quickshell theme-file write.
   See `themes/apply-theme:228-256`, `themes/lib/resolve.py:76-110`,
   `themes/lib/orchestrator.py:15-37`, and `themes/lib/targets/gtk.py:32-43`.
7. After the immediate reconcile, the scheduler stops any existing
   `sun-event-*` timers and recreates the next sunrise, sunset, and dark-on
   transient timers with `systemd-run --user --collect`. See
   `scripts/sun-schedule:154-170`, `scripts/sun-schedule:211-220`.
8. When a transient timer fires, it reruns the script with one of the event
   subcommands:
   `sunrise-action`, `sunset-action`, or `dark-on`. See
   `scripts/sun-schedule:223-236`.

## Resource Map

| Resource | Current writer path | Current reader path |
| --- | --- | --- |
| `hyprsunset` process | `scripts/sun-schedule`, `config/quickshell/DisplayService.qml`, `config/hypr/keybinds.conf` | `config/quickshell/DisplayService.qml` polls process status and arguments. |
| `themes/state.json` `dark_hint` value | `themes/apply-theme`, invoked by the scheduler, Quickshell settings, presets, or shell IPC | `themes/apply-theme` reloads it for every mutation; Quickshell settings reads it directly. |
| GTK dconf interface keys | `themes/lib/targets/gtk.py` via `on_apply()` | GTK apps and any consumer honoring the desktop color-scheme hint. |
| `~/.config/quickshell/GeneratedTheme.json` | `themes/lib/targets/quickshell.py` | `config/quickshell/Theme.qml` watches the file. `dark_hint` does not flow through this file today. |
