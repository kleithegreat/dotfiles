# Sun Schedule Architecture

## Scope

Current implementation map for solar scheduling, location resolution, and
cross-domain side effects as of 2026-04-03.

## Primary Implementation Surface

| Path | Current role | Evidence |
| --- | --- | --- |
| `home/default.nix` | Installs `desktopctl`, `hyprsunset`, and `geoclue2-with-demo-agent` into the user environment | `home/default.nix:33-45`, `home/default.nix:136-145` |
| `config/hypr/autostart.conf` | Starts `desktopctl daemon` as part of the Hyprland session | `config/hypr/autostart.conf:6-8` |
| `desktopctl/src/daemon/mod.rs` | Starts the solar scheduler and socket server with one shared night-light controller alongside the focus tracker | `desktopctl/src/daemon/mod.rs:27-50` |
| `desktopctl/src/daemon/night_light.rs` | Stores the live `auto` / `on` / `off` mode, remembers the manual temperature, derives the effective state from solar status, and is the only live writer of `hyprsunset` and `dark_hint` | `desktopctl/src/daemon/night_light.rs:14-162` |
| `desktopctl/src/daemon/solar.rs` | Recomputes solar status at startup, on every solar event, on `SIGUSR1`, and on the 2-hour repair tick, then hands the result to the night-light controller for reconciliation | `desktopctl/src/daemon/solar.rs:8-49` |
| `desktopctl/src/daemon/server.rs` | Exposes the daemon-owned `night_light.status`, `night_light.set`, and `night_light.toggle` methods over the Unix socket | `desktopctl/src/daemon/server.rs:18-147` |
| `desktopctl/src/night_light.rs` | Implements the `desktopctl night-light` CLI, socket client helpers, fallback status, and `hyprsunset` process inspection / start / stop helpers | `desktopctl/src/night_light.rs:9-318` |
| `desktopctl/src/solar.rs` | Resolves coordinates, computes sunrise/sunset, derives the scheduled state, and exposes `desktopctl sun status` | `desktopctl/src/solar.rs:40-202` |
| `desktopctl/src/theme/mod.rs` | Handles in-process `dark_hint` persistence for the daemon and routes theme-surface `dark_hint` requests back through the daemon-owned night-light API | `desktopctl/src/theme/mod.rs:61-78`, `desktopctl/src/theme/mod.rs:252-330` |
| `desktopctl/src/theme/targets/gtk.rs` | Applies GTK dark-preference side effects through dconf when `dark_hint` changes | `desktopctl/src/theme/targets/gtk.rs:44-71` |

## Neighbor And Requester Surfaces

| Path | Current role | Evidence |
| --- | --- | --- |
| `config/quickshell/DisplayService.qml` | Polls `desktopctl night-light status --json` and requests `desktopctl night-light on/off` instead of managing `hyprsunset` directly | `config/quickshell/DisplayService.qml:40-119`, `config/quickshell/DisplayService.qml:179-239` |
| `config/quickshell/popups/SettingsPopup.qml` | Reads theme state and still exposes `dark_hint` controls through `desktopctl theme ...`, whose `dark_hint` path is now mediated by the daemon | `config/quickshell/popups/SettingsPopup.qml:140-171`, `config/quickshell/popups/SettingsPopup.qml:891-896` |
| `config/quickshell/popups/settings/SettingsPresetEditor.qml` | Still allows presets to include `dark_hint`; preset application is delegated back through the daemon by `desktopctl theme preset` | `config/quickshell/popups/settings/SettingsPresetEditor.qml:396-485` |
| `config/quickshell/shell.qml` | Exposes a generic `theme.apply` IPC entry point that can still reach `desktopctl theme ...`; `dark_hint` requests are delegated by the CLI layer | `config/quickshell/shell.qml:395-414` |
| `config/hypr/keybinds.conf` | Requests daemon-owned override changes through `desktopctl night-light toggle` and `desktopctl night-light auto` | `config/hypr/keybinds.conf:74-75` |
| `config/quickshell/Theme.qml` | Watches `GeneratedTheme.json`; `dark_hint` still does not flow through that file | `config/quickshell/Theme.qml:8-27` |

## Runtime Flow

1. Hyprland starts `desktopctl daemon` through `config/hypr/autostart.conf:6-8`.
2. `desktopctl/src/daemon/mod.rs:27-50` starts the solar scheduler and socket
   server with one shared night-light controller under the shared daemon
   runtime.
3. `desktopctl/src/solar.rs:67-93` resolves coordinates from the cached
   `sun-schedule/location.json`, then `where-am-i`, then the hardcoded
   fallback `30.6280, -96.3344`.
4. `desktopctl/src/solar.rs:95-149` derives sunrise, sunset, current night
   state, dark-hint state, and the next event timestamps for the current
   location.
5. `desktopctl/src/daemon/solar.rs:16-23` stores that scheduled state in the
   shared controller and immediately asks the controller to reconcile the
   effective mode.
6. `desktopctl/src/daemon/night_light.rs:123-162` derives the live desired
   state from the current mode: `auto` follows the solar status, `on` forces
   `hyprsunset` on plus `dark_hint = true`, and `off` forces `hyprsunset` off
   plus `dark_hint = false`.
7. `desktopctl/src/night_light.rs:145-175` inspects the current `hyprsunset`
   process, starts or stops it as needed, and persists `dark_hint` through the
   existing theme path only when the effective value actually changes.
8. `desktopctl/src/daemon/server.rs:68-125` serves the daemon-owned status and
   override methods so CLI callers and Quickshell can request mutations without
   becoming direct writers themselves.

## Resource Map

| Resource | Current writer path | Current reader path |
| --- | --- | --- |
| `hyprsunset` process | `desktopctl/src/daemon/night_light.rs` via `desktopctl/src/night_light.rs` helpers | `desktopctl/src/night_light.rs` inspects it for status; Quickshell reads the daemon-reported status instead of polling the process directly. |
| `$XDG_DATA_HOME/desktopctl/desktopctl.db` `theme_state.dark_hint` row | `desktopctl/src/theme/mod.rs`, invoked in-process by the daemon controller or by theme-surface requests that delegate through the daemon | `desktopctl theme` reloads it for every mutation; Quickshell settings reads it through `desktopctl theme status --json`. |
| GTK dconf interface keys | `desktopctl/src/theme/targets/gtk.rs` via `on_apply()` | GTK apps and any consumer honoring the desktop color-scheme hint. |
| `~/.config/quickshell/GeneratedTheme.json` | `desktopctl/src/theme/targets/quickshell.rs` | `config/quickshell/Theme.qml` watches the file. `dark_hint` does not flow through this file today. |
