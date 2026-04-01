# Hyprland Architecture

## Scope

This document describes the current Hyprland session architecture in this repo as of April 1, 2026. It is based on:

- `config/hypr/*`
- `hosts/laptop/*` and `hosts/desktop/*`
- `home/default.nix`
- Hyprland-related sections of `docs/theming/SPEC.md`

## Top-Level Assembly

The session entry point is `config/hypr/hyprland.conf`. It is intentionally small and only defines the source graph:

1. `~/.config/hypr/monitors.conf`
2. `~/.config/hypr/env.conf`
3. `~/.config/hypr/cursor.conf`
4. `~/.config/hypr/input.conf`
5. `~/.config/hypr/input-devices.conf`
6. `~/.config/hypr/colors.conf`
7. `~/.config/hypr/appearance.conf`
8. `~/.config/hypr/plugins.conf`
9. `~/.config/hypr/keybinds.conf`
10. `~/.config/hypr/rules.conf`
11. `~/.config/hypr/autostart.conf`

That order is significant. Hyprland parses sourced files linearly, so earlier sources define inputs for later ones. The current order makes host selection happen first, then generated theme inputs, then appearance, then plugins, keybinds, rules, and startup commands. This matches the wiki's `source` behavior documentation: <https://wiki.hypr.land/0.52.0/Configuring/Keywords/#sourcing-multi-file>

## Host-Specific Split

The active config graph is selected by Home Manager in `home/default.nix`, not only by the files under `config/hypr/`.

- `~/.config/hypr/input-devices.conf` points to `hosts/laptop/input-devices.conf` on the laptop and `hosts/desktop/input-devices.conf` on the desktop.
- `~/.config/hypr/monitors.conf` points to `hosts/laptop/monitors.conf` on the laptop and `hosts/desktop/monitors.conf` on the desktop.
- `~/.config/hypr/env.conf` points to `config/hypr/env.conf` on the laptop and `hosts/desktop/env.conf` on the desktop.

This means `hyprland.conf` always sources the same target paths, while `home/default.nix` swaps the underlying files per host. The result is a stable top-level include graph with host variance pushed to the symlink layer.

Two implications matter:

- `config/hypr/monitors.conf` exists in the repo, but the known hosts do not currently symlink it into `~/.config/hypr/monitors.conf`.
- `hosts/desktop/env.conf` is not purely environment variables; it also carries a desktop-only `exec-once` for Solaar.

## Theme Integration

The theme system is split into base config plus generated overlays.

- `~/.config/hypr/colors.conf` is a generated standalone file. `docs/theming/SPEC.md` describes it as the source of `$theme_*` variables and says it reloads via `hyprctl reload`.
- `appearance.conf` immediately sources `~/.config/hypr/appearance-theme.conf`, another generated file used for runtime appearance values such as gaps, borders, rounding, blur, and animation settings.
- `hyprlock.conf` sources `~/.config/hypr/colors.conf` directly so the lock screen inherits the same palette variables as the compositor.
- `plugins.conf` consumes the same theme variables for `hyprbars` and `hyprexpo`.

This yields a three-layer model:

1. Base module files in `config/hypr/`
2. Generated theme variable file: `colors.conf`
3. Generated runtime appearance override file: `appearance-theme.conf`

`docs/theming/SPEC.md` still describes a `pluginsettings.conf` base file, but the live source graph now uses `plugins.conf`. Architecturally, `plugins.conf` is the real theming consumer today.

Relevant theming references:

- `docs/theming/SPEC.md` generated-file layout: `colors.conf`, `appearance-theme.conf`
- `docs/theming/SPEC.md` Hyprland target registry: `hyprland` and `hypr_appearance`
- `docs/theming/SPEC.md` live appearance flow: Quickshell settings update theme state, `apply-theme` regenerates `appearance-theme.conf`, and Hyprland reloads

## Appearance Layer

`appearance.conf` holds the stable compositor look-and-feel defaults:

- `general { layout = dwindle; allow_tearing = false; }`
- shared animation curve and window/workspace animations
- `dwindle` behavior such as `pseudotile` and `preserve_split`
- `misc` cleanup such as disabling the logo, splash, and default wallpaper

The file is deliberately split so that long-lived defaults stay in version control while the generated `appearance-theme.conf` can override pure appearance values at runtime.

## Input Model

Input settings are divided into three layers:

1. `input.conf` for shared defaults
2. `input-devices.conf` for host-specific device overrides
3. `cursor.conf` for generated cursor settings

Shared defaults in `input.conf` include:

- US keyboard layout
- `follow_mouse = 1`
- mouse sensitivity and flat acceleration
- shared scroll factor
- `cursor { no_hardware_cursors = true }`

Host-specific overrides then refine that:

- laptop: touchpad natural scroll, reduced touchpad scroll factor, 3-finger horizontal workspace gesture
- desktop: per-device mouse sensitivities for the Logitech G Pro and MX Master 2S

## Autostart Sequence

`autostart.conf` is the session bootstrap file. In order, it does the following:

1. Imports `SSH_AUTH_SOCK` from the user systemd environment and propagates the environment to D-Bus and systemd activation.
2. Starts `hyprpolkitagent`.
3. Seeds `/tmp/quickshell-brightness` from `brightnessctl`.
4. Launches Quickshell via `scripts/launch-quickshell.sh`.
5. Starts the `vicinae` server.
6. Starts `swww-daemon` and applies the wallpaper.
7. Starts `hypridle`.
8. Starts `snappy-switcher --daemon`.
9. Starts the focus-time daemon.
10. Starts Easy Effects in service mode.

The important architectural point is that Hyprland is the session orchestrator for several adjacent services:

- Quickshell for shell UI
- `hypridle` for idle detection
- `hyprlock` indirectly via `loginctl lock-session` and `hypridle`
- `swww` for wallpaper
- `snappy-switcher`, `vicinae`, and other user daemons

## Keybind Scheme

`keybinds.conf` uses a single primary modifier:

- `$mainMod = SUPER`

The file is grouped by function rather than by dispatcher type:

- core app and window actions
- focus movement
- workspace selection and window-to-workspace moves
- workspace scrolling
- mouse move/resize binds
- brightness, volume, media, night-light, screenshots, and lock
- Quickshell IPC toggles
- Quickshell restart
- window switcher
- plugin-specific workspace overview

The most important integration point is the Quickshell IPC block:

- `SUPER + Escape` toggles the power menu
- `SUPER + Shift + N` toggles the notification drawer
- `SUPER + T` toggles settings

All three call `qs -p ~/repos/dotfiles/config/quickshell ipc call ...`, so Hyprland owns the keybinds but Quickshell owns popup state and UI behavior. `SUPER + Shift + Q` restarts Quickshell through the same repo-local launch script.

Other notable bindings:

- number row workspaces plus `SUPER + CTRL + Left/Right` for relative workspace movement
- `ALT + Tab` and `ALT + Shift + Tab` delegate window switching to `snappy-switcher`
- `SUPER + grave` toggles the `hyprexpo` overview through `hyprctl dispatch hyprexpo:expo toggle`

## Window Rules And Layer Rules

`rules.conf` is organized by outcome:

- float utility windows
- float and center dialog-like windows
- app-specific size and placement exceptions
- layer-surface rules
- plugin-specific window behavior

The file mixes current anonymous rule syntax and named rule blocks:

- anonymous `windowrule = ...` lines for simple one-off float, size, and center cases
- a named `windowrule {}` block to disable `hyprbars` on tiled windows
- named `layerrule {}` blocks for Vicinae blur and no-animation behavior

Current rule organization by responsibility:

- utility apps such as Pavucontrol, Easy Effects, Ark, Filelight, and Zoom float
- KDE portal file picker gets a fixed floating size and centering
- the Bitwarden browser popup gets a specific floating geometry
- `hyprbars:no_bar = true` is applied whenever `match:float = false`
- Vicinae layer surfaces get blur and disabled animation

There are also commented Quickshell layer rules for namespace-based blur. Those show the intended pattern for styling shell layer surfaces when needed.

## Plugin Configuration

`plugins.conf` loads two plugins from the Nix-provided `HYPR_PLUGIN_DIR`:

- `libhyprbars.so`
- `libhyprexpo.so`

It also contains the live plugin settings:

- `hyprbars` uses theme-derived bar colors, theme fonts, and bar buttons wired to Hyprland dispatchers.
- `hyprexpo` sets columns, gap size, background color, and workspace selection method.

Plugin behavior is tied back into the rule layer through the named `no-hyprbars-on-tiled` window rule in `rules.conf`.

## Idle And Lock Flow

Idle and lock are intentionally split between Hyprland, `hypridle`, and `hyprlock`.

- Hyprland starts `hypridle` from `autostart.conf`.
- `hypridle.conf` uses the standard lock/suspend sequence:
  - `lock_cmd = pidof hyprlock || hyprlock`
  - `before_sleep_cmd = loginctl lock-session`
  - `after_sleep_cmd = hyprctl dispatch dpms on`
- Listeners then dim at 5 minutes, lock at 10, DPMS off at 15, and suspend at 30.
- `SUPER + L` also locks through `loginctl lock-session`.

`hyprlock.conf` is theme-aware and widget-driven:

- it sources `colors.conf`
- it enables fingerprint auth
- it uses a blurred `screenshot` background
- it defines time, date, greeting, and password-input widgets for all monitors by leaving `monitor =` empty

This keeps session idling, session locking, and lock-screen visuals in separate files while preserving a single shared color system.

## Monitor Configuration

Monitor selection follows the same host split as input:

- `hosts/laptop/monitors.conf` pins the internal `eDP-1` panel and then falls back to `monitor = , preferred, auto, 1` for anything else
- `hosts/desktop/monitors.conf` pins `HDMI-A-1` at `1920x1080@143.98` and also keeps the same catch-all fallback

The fallback rule is important: it allows ad hoc external monitors to come up without additional per-output entries, while the known primary display on each host still gets explicit geometry.

## Design Summary

The Hyprland setup is modular in three different ways at once:

- source-level modularity inside `hyprland.conf`
- host-level modularity via Home Manager symlink selection
- theme-level modularity via generated `colors.conf` and `appearance-theme.conf`

The practical result is a small, stable entry point that delegates:

- hardware differences to `hosts/*`
- look-and-feel to generated theme files
- startup behavior to `autostart.conf`
- UI surfaces to Quickshell
- special window behavior to `rules.conf`
- plugin visuals to `plugins.conf`
