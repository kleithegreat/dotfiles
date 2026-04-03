# Sun Schedule Architecture

## Scope

Current implementation map for solar scheduling, location resolution, and
cross-domain side effects as of 2026-04-03.

## Primary Implementation Surface

| Path | Current role | Evidence |
| --- | --- | --- |
| `home/default.nix` | Installs `desktopctl`, `hyprsunset`, and `geoclue2-with-demo-agent` into the user environment | `home/default.nix:33-45`, `home/default.nix:136-145` |
| `config/hypr/autostart.conf` | Starts `desktopctl daemon` as part of the Hyprland session | `config/hypr/autostart.conf:6-8` |
| `desktopctl/src/daemon/mod.rs` | Starts the solar scheduler alongside the focus tracker and socket server | `desktopctl/src/daemon/mod.rs:19-100` |
| `desktopctl/src/daemon/solar.rs` | Applies the current solar state, sleeps until the next solar event or 2-hour repair tick, drives `hyprsunset`, and updates `dark_hint` through the theme subsystem | `desktopctl/src/daemon/solar.rs:12-99` |
| `desktopctl/src/solar.rs` | Resolves coordinates, computes sunrise/sunset, derives current state, and exposes `desktopctl sun status` | `desktopctl/src/solar.rs:48-160`, `desktopctl/src/solar.rs:215-259` |
| `desktopctl/src/theme/mod.rs` | Handles `dark_hint` persistence through the normal theme-state validation and apply path | `desktopctl/src/theme/mod.rs:69-90`, `desktopctl/src/theme/mod.rs:252-518` |
| `desktopctl/src/theme/targets/gtk.rs` | Applies GTK dark-preference side effects through dconf when `dark_hint` changes | `desktopctl/src/theme/targets/gtk.rs:44-71` |

## Neighbor And Competing Surfaces

| Path | Current role | Evidence |
| --- | --- | --- |
| `config/quickshell/DisplayService.qml` | Polls `hyprsunset`, starts it directly, stops it with `pkill`, and restarts it to apply temperature changes | `config/quickshell/DisplayService.qml:39-137`, `config/quickshell/DisplayService.qml:217-285` |
| `config/quickshell/popups/SettingsPopup.qml` | Reads theme state and can still mutate `dark_hint` through `desktopctl theme set` and `desktopctl theme preset` | `config/quickshell/popups/SettingsPopup.qml:158-223`, `config/quickshell/popups/SettingsPopup.qml:666-672` |
| `config/quickshell/popups/settings/SettingsPresetEditor.qml` | Still allows presets to include `dark_hint` | `config/quickshell/popups/settings/SettingsPresetEditor.qml:396-485` |
| `config/quickshell/shell.qml` | Exposes a generic `theme.apply` IPC entry point that can invoke `desktopctl theme ...` | `config/quickshell/shell.qml:299-306` |
| `config/hypr/keybinds.conf` | Adds manual `hyprsunset` stop/start keybinds outside the scheduler | `config/hypr/keybinds.conf:73-75` |
| `config/quickshell/Theme.qml` | Watches `GeneratedTheme.json`; `dark_hint` still does not flow through that file | `config/quickshell/Theme.qml:8-27` |

## Runtime Flow

1. Hyprland starts `desktopctl daemon` through `config/hypr/autostart.conf:6-8`.
2. `desktopctl/src/daemon/mod.rs:26-57` starts the solar scheduler as an async
   task under the shared daemon runtime.
3. `desktopctl/src/solar.rs:75-101` resolves coordinates from the cached
   `sun-schedule/location.json`, then `where-am-i`, then the hardcoded
   fallback `30.6280, -96.3344`.
4. `desktopctl/src/solar.rs:103-160` derives sunrise, sunset, current night
   state, dark-hint state, and the next event timestamps for the current
   location.
5. `desktopctl/src/daemon/solar.rs:20-23` applies the current state
   immediately. `hyprsunset` is started or stopped in-process, and
   `theme::set_dark_hint()` persists the desired `dark_hint` value.
6. `desktopctl/src/daemon/solar.rs:25-41` then waits for the earlier of:
   the next sunrise/sunset/dark-on event, a `SIGUSR1` recompute request, a
   2-hour repair tick, or daemon shutdown.
7. When the next solar event fires, `desktopctl/src/daemon/solar.rs:55-65`
   applies the event-specific transition directly instead of creating transient
   systemd timers.

## Resource Map

| Resource | Current writer path | Current reader path |
| --- | --- | --- |
| `hyprsunset` process | `desktopctl/src/daemon/solar.rs`, `config/quickshell/DisplayService.qml`, `config/hypr/keybinds.conf` | `config/quickshell/DisplayService.qml` polls process status and arguments. |
| `$XDG_DATA_HOME/desktopctl/desktopctl.db` `theme_state.dark_hint` row | `desktopctl theme`, invoked by the solar scheduler, Quickshell settings, presets, or shell IPC | `desktopctl theme` reloads it for every mutation; Quickshell settings reads it through `desktopctl theme status --json`. |
| GTK dconf interface keys | `desktopctl/src/theme/targets/gtk.rs` via `on_apply()` | GTK apps and any consumer honoring the desktop color-scheme hint. |
| `~/.config/quickshell/GeneratedTheme.json` | `desktopctl/src/theme/targets/quickshell.rs` | `config/quickshell/Theme.qml` watches the file. `dark_hint` does not flow through this file today. |
