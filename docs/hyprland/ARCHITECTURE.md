# Hyprland Architecture

## Scope

Current implementation map for `config/hypr/`, the host-selected Hyprland
fragments, and the generated theme inputs as of 2026-04-02.

## Source Graph

`config/hypr/hyprland.conf` is intentionally small and only defines the source
order:

| Order | Source | Role |
| --- | --- | --- |
| 1 | `~/.config/hypr/monitors.conf` | Output layout |
| 2 | `~/.config/hypr/env.conf` | Session environment and host-specific env fragments |
| 3 | `~/.config/hypr/cursor.conf` | Generated cursor environment |
| 4 | `~/.config/hypr/input.conf` | Shared input defaults |
| 5 | `~/.config/hypr/input-devices.conf` | Host-specific device overrides |
| 6 | `~/.config/hypr/colors.conf` | Generated `$theme_*` variables |
| 7 | `~/.config/hypr/appearance.conf` | Stable appearance defaults plus generated appearance overrides |
| 8 | `~/.config/hypr/plugins.conf` | Plugin loading and plugin theming |
| 9 | `~/.config/hypr/keybinds.conf` | Keybinds and external dispatcher integration |
| 10 | `~/.config/hypr/rules.conf` | Window and layer rules |
| 11 | `~/.config/hypr/autostart.conf` | Session bootstrap |

## Host Selection

`flake.nix` defines three hosts — `vm`, `laptop`, and `desktop` — each passing
its `hostName` through `specialArgs` to Home Manager (`flake.nix:54-56`).
`home/default.nix` uses `if hostName == "laptop" ... else if hostName ==
"desktop" ... else` conditionals to select host-specific fragments
(`home/default.nix:188-215`). The `else` branch provides safe minimal defaults,
which is what the `vm` host and any future host without explicit handling
receives.

| Target path | Laptop | Desktop | Fallback (VM and others) |
| --- | --- | --- | --- |
| `~/.config/hypr/input-devices.conf` | `hosts/laptop/input-devices.conf` | `hosts/desktop/input-devices.conf` | Empty file |
| `~/.config/hypr/monitors.conf` | `hosts/laptop/monitors.conf` | `hosts/desktop/monitors.conf` | `monitor = ,preferred,auto,1` |
| `~/.config/hypr/env.conf` | `config/hypr/env.conf` | `hosts/desktop/env.conf` | Empty file |

The remaining source-graph files — `hyprland.conf`, `appearance.conf`,
`input.conf`, `keybinds.conf`, `rules.conf`, `plugins.conf`, `autostart.conf`,
`hypridle.conf`, and `hyprlock.conf` — are deployed identically on all hosts
from `config/hypr/` (`home/default.nix:184-199`).

`config/hypr/monitors.conf` exists in the repo as a template, but all known
physical hosts use host-specific monitor files. The fallback branch inlines the
generic monitor rule rather than sourcing this file.

## Theme Integration

| File | Current role |
| --- | --- |
| `colors.conf` | Generated palette, font, and semantic `$theme_*` variables |
| `appearance-theme.conf` | Generated runtime appearance values such as gaps, borders, rounding, blur, and animation toggles |
| `appearance.conf` | Stable compositor defaults that source `appearance-theme.conf` |
| `hyprlock.conf` | Sources `colors.conf` so the lock screen shares the compositor palette |
| `plugins.conf` | Consumes the same theme variables for `hyprbars` and `hyprexpo` |

`plugins.conf` is the live plugin file. `pluginsettings.conf` is not part of the
active source graph.

## Subsystem Ownership

| File | Owns |
| --- | --- |
| `input.conf` | Shared keyboard, pointer, cursor, and gesture defaults |
| `autostart.conf` | Session bootstrap: `swww-daemon` lifecycle, Quickshell, `hypridle`, Vicinae, Snappy Switcher, focus-time, Easy Effects, and related session helpers. Wallpaper application is owned by the theming pipeline's `wallpaper` target (`docs/theming/SPEC.md`). |
| `keybinds.conf` | Primary modifier scheme, workspace binds, media/brightness binds, Quickshell IPC binds, and external launcher/switcher actions |
| `rules.conf` | Floating/dialog rules, app-specific geometry, layer rules, and plugin rule glue |
| `plugins.conf` | Loading `hyprbars` and `hyprexpo` from `HYPR_PLUGIN_DIR` plus their theme-facing settings |
| `hypridle.conf` and `hyprlock.conf` | Idle, lock, DPMS, suspend, and lock-screen presentation |

Monitor behavior follows the same host split as inputs:

- The laptop pins `eDP-1` and keeps a fallback `monitor = , preferred, auto, 1`
  rule for everything else.
- The desktop pins `HDMI-A-1` and keeps the same catch-all fallback.

Desktop-specific NVIDIA environment and resume quirks live in
`docs/nvidia/QUIRKS.md`.
