# Hyprland Architecture

## Scope

Current implementation map for `config/hypr/`, the host-selected Hyprland
fragments, and the generated theme inputs as of 2026-04-16.

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
| 6 | `~/.config/hypr/input-runtime.conf` | `desktopctl`-managed shared pointer overrides |
| 7 | `~/.config/hypr/colors.conf` | Generated `$theme_*` variables |
| 8 | `~/.config/hypr/appearance.conf` | Stable appearance defaults plus generated appearance overrides |
| 9 | `~/.config/hypr/animations-override.conf` | `desktopctl`-managed animation and bezier overrides |
| 10 | `~/.config/hypr/plugins.conf` | Plugin loading and plugin theming |
| 11 | `~/.config/hypr/keybinds.conf` | Keybinds and external dispatcher integration |
| 12 | `~/.config/hypr/keybinds-override.conf` | `desktopctl`-managed keybind overrides |
| 13 | `~/.config/hypr/rules.conf` | Window and layer rules |
| 14 | `~/.config/hypr/autostart.conf` | Session bootstrap plus `autostart-host.conf` include |

## Host Selection

`flake.nix` defines two hosts — `laptop` and `desktop` — and now
passes a structured `host` record through both `specialArgs` and
`home-manager.extraSpecialArgs`.
`home/xdg.nix` selects the host-specific Hyprland fragments through
`host.hyprland.*` path facts instead of string-matching the host name. Null host
paths fall back to safe minimal defaults for any future host without explicit
Hyprland fragments.

| Target path | Laptop | Desktop | Fallback |
| --- | --- | --- | --- |
| `~/.config/hypr/autostart-host.conf` | Empty file | `hosts/desktop/autostart.conf` | Empty file |
| `~/.config/hypr/input-devices.conf` | `hosts/laptop/input-devices.conf` | `hosts/desktop/input-devices.conf` | Empty file |
| `~/.config/hypr/monitors.conf` | `hosts/laptop/monitors.conf` | `hosts/desktop/monitors.conf` | `monitor = ,preferred,auto,1` |
| `~/.config/hypr/env.conf` | `config/hypr/env.conf` | `hosts/desktop/env.conf` | Empty file |

The remaining source-graph files — `hyprland.conf`, `appearance.conf`,
`input.conf`, `keybinds.conf`, `rules.conf`, `plugins.conf`, `autostart.conf`,
`hypridle.conf`, and `hyprlock.conf` — are deployed identically on all hosts
from `config/hypr/` via the shared `xdg.configFile` mappings in `home/xdg.nix`.

Home Manager now also bootstraps empty `~/.config/hypr/input-runtime.conf`,
`~/.config/hypr/animations-override.conf`, and
`~/.config/hypr/keybinds-override.conf`
on every host before running `desktopctl theme sync`
through the `home.activation.applyTheme` hook in `home/default.nix`.
`desktopctl hypr input set ...` rewrites that
file later when the Mouse settings page updates shared pointer defaults.

Current host input fragments differ materially:

- `hosts/laptop/input-devices.conf` keeps touchpad-only behavior: natural
  scrolling, a reduced touchpad `scroll_factor`, the existing three-finger
  horizontal workspace swipe, and a three-finger swipe-up that dispatches
  `hyprexpo:expo toggle` through Hyprland's core `gesture` keyword
  in the laptop input fragment.
- `hosts/desktop/input-devices.conf` currently only adjusts per-device mouse
  sensitivity for the Logitech G Pro and MX Master 2S
  in the desktop input fragment.
- `hosts/desktop/env.conf` still carries the dedicated-NVIDIA session variables
  and now also exports `DESKTOPCTL_IDLE_INHIBIT_DEFAULT=1`, which
  `config/quickshell/IdleInhibitService.qml` reads at shell startup so the
  desktop session boots with idle inhibit already active.
- `hosts/desktop/autostart.conf` starts Solaar hidden for the desktop session
  and keeps the Logitech MX Master 2S smart-shift tweak in that desktop-only
  startup fragment instead of mixing either concern into `hosts/desktop/env.conf`.

## Theme And Runtime Integration

| File | Current role |
| --- | --- |
| `colors.conf` | Generated palette, font, and semantic `$theme_*` variables |
| `appearance-theme.conf` | Generated runtime appearance values such as gaps, borders, rounding, blur, and animation toggles |
| `input-runtime.conf` | Generated runtime pointer overrides written by `desktopctl hypr input` |
| `animations-override.conf` | Generated bezier curves and per-animation overrides written by `desktopctl hypr animations` |
| `keybinds-override.conf` | Generated unbind + rebind pairs written by `desktopctl hypr keybinds` |
| `appearance.conf` | Stable compositor defaults that source `appearance-theme.conf` |
| `hyprlock.conf` | Sources `colors.conf` so the lock screen shares the compositor palette |
| `plugins.conf` | Consumes the same theme variables for `hyprbars` and `hyprexpo` |

## Subsystem Ownership

| File | Owns |
| --- | --- |
| `input.conf` | Shared keyboard, pointer, cursor, and gesture defaults that remain the fallback when no runtime override exists |
| `input-runtime.conf` | Shared mouse defaults written by `desktopctl hypr input`; the file is sourced after `input-devices.conf` in `config/hypr/hyprland.conf`, so it layers on top of the shared base config without editing static or host fragments. The rewrite logic lives in `desktopctl/src/hypr.rs`. |
| `animations-override.conf` | Bezier curve definitions and per-animation overrides written by `desktopctl hypr animations`; sourced after `appearance.conf` so GUI-modified animations layer on top of hand-edited base animations. Only overridden animations are written; untouched animations keep their `appearance.conf` values. |
| `keybinds-override.conf` | Unbind + rebind pairs written by `desktopctl hypr keybinds`; sourced after `keybinds.conf` so GUI-remapped keybinds replace their original combos. Uses concrete resolved values rather than `$mainMod` variables. |
| `autostart.conf` and `autostart-host.conf` | Shared session bootstrap lives in `config/hypr/autostart.conf`, which starts `desktopctl daemon`, Quickshell, wallpaper bootstrap, `hypridle`, Vicinae, Snappy Switcher, Easy Effects, Bitwarden, and related helpers, then sources `~/.config/hypr/autostart-host.conf` for host-only additions such as the desktop's Logitech mouse tuning. Wallpaper selection itself remains owned by the theming pipeline's `wallpaper` target (`docs/theming/SPEC.md`). |
| `keybinds.conf` | Primary modifier scheme, descriptive `bindd` / `bindde` bindings, directional focus on `SUPER+Arrow`, workspace cycling on `SUPER+ALT+Left/Right`, media/brightness repeat binds, Quickshell IPC binds that resolve the shell path through `${DESKTOPCTL_REPO:-$HOME/repos/dotfiles}`, and external launcher/switcher actions |
| `rules.conf` | Floating/dialog rules, app-specific geometry, layer rules, and plugin rule glue |
| `plugins.conf` | Loading `hyprbars` and `hyprexpo` from `HYPR_PLUGIN_DIR` plus their theme-facing settings |
| `hypridle.conf` and `hyprlock.conf` | Idle, lock, DPMS, suspend, and lock-screen presentation. `config/quickshell/IdleInhibitService.qml` can temporarily suppress the hypridle timers by holding `systemd-inhibit --what=idle`, but it does not edit these files. |

`system/configuration.nix` also wires the repo-local Hyprland patch stack into the
installed compositor and plugin packages. The local
`patches/hyprland/hyprland-floating-top-decoration-rounding-0.54.patch`
extends the renderer's rounding shader so both texture and rect passes can
select which corners stay rounded; `src/desktop/view/Window.cpp`
`CWindow::shouldSquareTopCorners()` then uses
`DecorationPositioner::getBoxWithIncludedDecos` to square the main surface's
top edge only when a top decoration is part of the window. The matching
`patches/hyprland-plugins/hyprbars-hyprland-0.54.patch` keeps
`hyprbars/barDeco.cpp` on upstream's `DECORATION_LAYER_UNDER` and renders the
bar background with top-only rounded corners instead of the old oversized
rounded-rect fill hack, so the titlebar does not seep into the window sides
while the main surface keeps its squared join. For those square-top bars, the
patch also skips the old stencil-dependent background path so `hyprexpo`'s
offscreen workspace captures can keep the bar background visible.

Monitor behavior follows the same host split as inputs:

- The laptop pins `eDP-1` and keeps a fallback `monitor = , preferred, auto, 1`
  rule for everything else.
- The desktop pins `HDMI-A-1` and keeps the same catch-all fallback.

Desktop-specific NVIDIA environment and resume quirks live in
`docs/nvidia/QUIRKS.md`.
