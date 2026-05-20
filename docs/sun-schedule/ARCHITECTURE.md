# Sun Schedule Architecture

## Scope

Current implementation map for solar scheduling, location resolution, and
cross-domain side effects as of 2026-05-19.

For package installation and Hyprland session startup ownership, see
`docs/nix/ARCHITECTURE.md` and `docs/hyprland/ARCHITECTURE.md`.

## Primary Implementation Surface

| Path | Current role | Evidence |
| --- | --- | --- |
| `config/hypr/autostart.conf` | Starts `desktopctl daemon` as part of the Hyprland session | The `exec-once = desktopctl daemon &` entry |
| `desktopctl/src/daemon/mod.rs` | Starts the solar scheduler and socket server with one shared night-light controller alongside the focus tracker | The daemon `run()` / `run_async()` bootstrap |
| `desktopctl/src/daemon/night_light.rs` | Stores the live `auto` / `on` / `off` mode, remembers the manual temperature, derives the effective state from solar status, tracks pending scheduled `dark_hint` startup reconciliation and edge transitions, and is the only live writer of `hyprsunset` | `Controller`, `update_solar_status()`, `dark_hint_transition()`, `desired_state()`, and `apply_desired_state()` in `desktopctl/src/daemon/night_light.rs` |
| `desktopctl/src/daemon/solar.rs` | Recomputes solar status at startup, on every solar event, on `SIGUSR1`, and on the 2-hour repair tick, then hands the result to the night-light controller for reconciliation | The scheduler loop in `desktopctl/src/daemon/solar.rs` |
| `desktopctl/src/daemon/server.rs` | Exposes the daemon-owned `night_light.status`, `night_light.set`, and `night_light.toggle` methods over the Unix socket | The socket-method handlers in `desktopctl/src/daemon/server.rs` |
| `desktopctl/src/night_light.rs` | Implements the `desktopctl night-light` CLI, socket client helpers, fallback status, and `hyprsunset` process inspection / start / stop helpers | The CLI commands and `hyprsunset` helper functions in `desktopctl/src/night_light.rs` |
| `desktopctl/src/solar.rs` | Resolves coordinates from a six-hour cache, GeoClue, stale-cache fallback, or the deterministic College Station fallback; rejects non-finite or out-of-range cache/GeoClue coordinates; computes sunrise/sunset; derives the separate night-light and `dark_hint` schedules; and exposes `desktopctl sun status` | The location-resolution helpers and `sun status` implementation in `desktopctl/src/solar.rs` |
| `desktopctl/src/theme/mod.rs` | Handles `dark_hint` persistence and target application for both daemon-triggered scheduled writes and direct theme CLI writes | `set_dark_hint()` plus the theme command handlers in `desktopctl/src/theme/mod.rs` |
| `desktopctl/src/theme/targets/gtk.rs` | Applies GTK dark-preference side effects through dconf when `dark_hint` changes | The `on_apply()` implementation in `desktopctl/src/theme/targets/gtk.rs` |

## Neighbor And Requester Surfaces

| Path | Current role | Evidence |
| --- | --- | --- |
| `config/quickshell/DisplayService.qml` | Polls `desktopctl night-light status --json` and requests `desktopctl night-light on/off/auto` instead of managing `hyprsunset` directly | The display status loaders and request handlers in `config/quickshell/DisplayService.qml` |
| `config/quickshell/popups/CalendarPopup.qml` | Reuses `desktopctl sun status` as a read-only coordinate/sun-time surface for the calendar popup's toggleable weather view instead of reimplementing location resolution inside Quickshell | The popup-local `sunStatusProc`, `applySunStatus(...)`, and weather refresh path in `config/quickshell/popups/CalendarPopup.qml` |
| `config/quickshell/popups/SettingsPopup.qml` | Reads theme state and exposes `dark_hint` controls through `desktopctl theme set dark_hint ...`, which persists and applies `dark_hint` directly without touching daemon mode | The theme-state loading path plus the `dark_hint` controls in `config/quickshell/popups/SettingsPopup.qml` |
| `config/quickshell/popups/settings/SettingsPresetEditor.qml` | Allows presets to include `dark_hint`; preset application persists `dark_hint` directly via the theme pipeline without routing through the daemon | The preset-field editor and save flow in `config/quickshell/popups/settings/SettingsPresetEditor.qml` |
| `config/quickshell/shell.qml` | Exposes a generic `theme.apply` IPC entry point that can reach `desktopctl theme ...`; `dark_hint` requests are handled directly by the theme pipeline | The `theme.apply` IPC handler in `config/quickshell/shell.qml` |
| `config/hypr/keybinds.conf` | Requests daemon-owned override changes through `desktopctl night-light toggle` and `desktopctl night-light auto` | The `F8` / `F9` night-light bindings in `config/hypr/keybinds.conf` |
| `config/quickshell/Theme.qml` | Watches `GeneratedTheme.json`; `dark_hint` still does not flow through that file | The generated-theme watcher in `config/quickshell/Theme.qml` |

## Runtime Flow

1. Hyprland starts `desktopctl daemon` through the `exec-once = desktopctl daemon &`
   entry in `config/hypr/autostart.conf`.
2. The daemon bootstrap in `desktopctl/src/daemon/mod.rs` starts the solar scheduler and socket
   server with one shared night-light controller under the shared daemon
   runtime.
3. The coordinate-resolution helpers in `desktopctl/src/solar.rs` resolve from
   the cached `sun-schedule/location.json` only while its mtime is no more than
   six hours old, then query `where-am-i`, then fall back to a stale but valid
   cache entry, then the hardcoded fallback `30.6280, -96.3344`, rejecting any
   non-finite or out-of-range coordinates before treating them as
   authoritative.
4. The schedule-derivation helpers in `desktopctl/src/solar.rs` derive sunrise,
   sunset, current night state, the local-clock `dark_hint` window state, and
   the next sunrise / sunset / dark-on / dark-off timestamps for the current
   location.
5. `solar::run()` in `desktopctl/src/daemon/solar.rs` stores that scheduled state in the
   shared controller and immediately asks the controller to reconcile the
   effective mode.
6. `Controller::update_solar_status` in `desktopctl/src/daemon/night_light.rs`
    marks the first solar status's current scheduled `dark_hint` value for
    one-time reconciliation, then compares later solar statuses with the
    previous one and marks a pending `dark_hint` update only when the scheduler
    has just crossed a 23:00 dark-on or 06:00 dark-off edge.
7. `desired_state()` and `apply_desired_state()` in `desktopctl/src/daemon/night_light.rs` derive the live desired
   `hyprsunset` state from the current mode: `auto` follows the solar night
   window, `on` forces `hyprsunset` on, and `off` forces `hyprsunset` off.
8. The `Controller::reconcile` path in `desktopctl/src/daemon/night_light.rs`
   uses the `hyprsunset` and `dark_hint` helpers in `desktopctl/src/night_light.rs`
   to inspect the current process, update a running `hyprsunset` instance
   through its IPC socket when only the temperature changed, fall back to a
   restart when IPC is unavailable, and apply the pending scheduled
   `dark_hint` edge once without reapplying the same value throughout the rest
   of that window.
9. Independent of the daemon, `desktopctl/src/theme/mod.rs` still lets
   `desktopctl theme set dark_hint ...` and preset application persist
   `dark_hint` directly.
10. The request handlers in `desktopctl/src/daemon/server.rs` serve the
   daemon-owned status and override methods so CLI callers and Quickshell can
   request `hyprsunset` mode changes without becoming direct writers
   themselves.
11. Independent read-only consumers such as `desktopctl sun status` and the
     calendar popup's weather view reuse the same resolved coordinates and solar
     timestamps without becoming their own location owners.

## Resource Map

| Resource | Current writer path | Current reader path |
| --- | --- | --- |
| `hyprsunset` process and IPC socket | `desktopctl/src/daemon/night_light.rs` via the helper functions in `desktopctl/src/night_light.rs` | `desktopctl/src/night_light.rs` inspects the process plus `~/.hyprsunset.sock` for live temperature state; Quickshell reads the daemon-reported status instead of polling either directly |
| `$XDG_DATA_HOME/desktopctl/desktopctl.db` `theme_state.dark_hint` row | `desktopctl/src/theme/mod.rs`, called either by the daemon controller when the scheduler crosses the 23:00 dark-on or 06:00 dark-off edge or directly by `desktopctl theme` surfaces | `desktopctl theme` reloads it for every mutation; Quickshell settings reads it through `desktopctl theme status --json` |
| GTK dconf interface keys | `desktopctl/src/theme/targets/gtk.rs` via `on_apply()` | GTK apps and any consumer honoring the desktop color-scheme hint |
| `~/.config/quickshell/GeneratedTheme.json` | `desktopctl/src/theme/targets/quickshell.rs` | `config/quickshell/Theme.qml` watches the file. `dark_hint` does not flow through this file today |
