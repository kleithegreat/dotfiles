# Hyprland Architecture

## Scope

Current implementation map for `config/hypr/`, the host-selected Hyprland
fragments, and the generated theme inputs as of 2026-05-19.

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
| `~/.config/hypr/autostart-host.conf` | `hosts/laptop/autostart.conf` | `hosts/desktop/autostart.conf` | Empty file |
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

- `hosts/laptop/input-devices.conf` keeps touchpad behavior: natural scrolling,
  a reduced touchpad `scroll_factor`, the existing three-finger horizontal
  workspace swipe, a three-finger swipe-up that dispatches `hyprexpo:expo
  toggle` through Hyprland's core `gesture` keyword, and the per-device
  sensitivity for the Logitech MX Master 2S. It also binds the laptop lid switch
  to `desktopctl hypr lid-switch closed/open --internal eDP-1` so closing the
  lid disables the hidden internal output when another monitor is active and
  opening the lid restores `eDP-1` from `preferred,auto,1`.
- `hosts/desktop/input-devices.conf` adjusts per-device mouse sensitivity for
  the Logitech G Pro and MX Master 2S in the desktop input fragment.
- `hosts/desktop/env.conf` still carries the dedicated-NVIDIA session variables
  and now also exports `DESKTOPCTL_IDLE_INHIBIT_DEFAULT=1`, which
  `config/quickshell/IdleInhibitService.qml` reads at shell startup so the
  desktop session boots with idle inhibit already active.
- `hosts/laptop/autostart.conf` and `hosts/desktop/autostart.conf` start Solaar
  hidden and apply the Logitech MX Master 2S smart-shift tweak through
  host-specific startup fragments instead of mixing either concern into
  `env.conf`; the laptop fragment first runs `desktopctl hypr lid-switch sync
  --internal eDP-1` to honor a lid that was already closed at session startup,
  explicitly sets the wheel to `Ratcheted`, and uses the MX Master 2S
  smart-shift maximum of `50`, while the desktop fragment keeps only the
  existing `50` smart-shift command.

## Theme And Runtime Integration

| File | Current role |
| --- | --- |
| `colors.conf` | Generated palette, font, and semantic `$theme_*` variables |
| `appearance-theme.conf` | Generated runtime appearance values such as gaps, borders, rounding, blur, and animation toggles |
| `input-runtime.conf` | Generated runtime pointer overrides written by `desktopctl hypr input` |
| `animations-override.conf` | Generated bezier curves and per-animation overrides written by `desktopctl hypr animations` |
| `keybinds-override.conf` | Generated unbind + rebind pairs written by `desktopctl hypr keybinds` |
| `appearance.conf` | Stable compositor defaults that source `appearance-theme.conf`; the static `dwindle` block keeps `preserve_split`, while pseudotiling is controlled at runtime through the `pseudo` dispatcher binding in `keybinds.conf` |
| `hyprlock.conf` | Sources `colors.conf` so the lock screen shares the compositor palette |
| `plugins.conf` | Consumes the same theme variables for `hyprbars` and `hyprexpo` |

## Subsystem Ownership

| File | Owns |
| --- | --- |
| `input.conf` | Shared keyboard, pointer, cursor, and gesture defaults that remain the fallback when no runtime override exists |
| `input-runtime.conf` | Shared mouse defaults written by `desktopctl hypr input`; the file is sourced after `input-devices.conf` in `config/hypr/hyprland.conf`, so it layers on top of the shared base config without editing static or host fragments. The rewrite logic lives in `desktopctl/src/hypr.rs`. |
| `animations-override.conf` | Bezier curve definitions and per-animation overrides written by `desktopctl hypr animations`; sourced after `appearance.conf` so GUI-modified animations layer on top of hand-edited base animations. Only overridden animations are written; untouched animations keep their `appearance.conf` values. |
| `keybinds-override.conf` | Unbind + rebind pairs written by `desktopctl hypr keybinds`; sourced after `keybinds.conf` so GUI-remapped keybinds replace their original combos. Uses concrete resolved values rather than `$mainMod` variables. |
| `autostart.conf` and `autostart-host.conf` | Shared session bootstrap lives in `config/hypr/autostart.conf`, which defines the `$cleanSessionEnv` token scrubber, imports `SSH_AUTH_SOCK` from the user manager, clears one-shot launch/workspace tokens before syncing the session environment into D-Bus/systemd activation, starts `hyprpolkitagent`, `desktopctl daemon`, Quickshell, Vicinae server, wallpaper bootstrap, `hypridle`, and Snappy Switcher through `$cleanSessionEnv`, then sources `~/.config/hypr/autostart-host.conf` for host-only additions such as Logitech mouse tuning. Easy Effects and Bitwarden remain installed but are no longer session autostarts. Wallpaper selection itself remains owned by the theming pipeline's `wallpaper` target (`docs/theming/SPEC.md`). |
| `keybinds.conf` | Primary modifier scheme, descriptive `bindd` / `bindde` bindings, directional focus on `SUPER+Arrow`, workspace cycling on `SUPER+ALT+Left/Right`, media/brightness repeat binds, Quickshell IPC binds that resolve the shell path through `${DESKTOPCTL_REPO:-$HOME/repos/dotfiles}`, and external launcher/switcher actions |
| `rules.conf` | Floating/dialog rules, app-specific geometry, layer rules, a `fullscreen_state 2 2` override for the old XWayland `Minecraft 1.10.2` client so it covers Quickshell's reserved top bar space, and plugin rule glue |
| `plugins.conf` | Loading `hyprbars` and `hyprexpo` from `HYPR_PLUGIN_DIR` plus their theme-facing settings |
| `hypridle.conf` and `hyprlock.conf` | Idle, lock, DPMS, suspend, and lock-screen presentation. `config/hypr/hypridle.conf` explicitly keeps `ignore_systemd_inhibit = false`, so `config/quickshell/IdleInhibitService.qml` can suppress the hypridle timers by holding `systemd-inhibit --what=idle`, and can separately block logind lid-switch handling with `systemd-inhibit --what=handle-lid-switch --mode=block`, but it does not edit these files. |

`system/configuration.nix` also wires the repo-local Hyprland patch stack into the
installed compositor and plugin packages. The local
`patches/hyprland/hyprland-floating-top-decoration-rounding-0.54.patch`
extends the renderer's rounding shader so both texture and rect passes can
select which corners stay rounded; `src/desktop/view/Window.cpp`
`CWindow::shouldSquareTopCorners()` then uses
`DecorationPositioner::getBoxWithIncludedDecos` to square the main surface's
top edge only when a top decoration is part of the window. The companion
`patches/hyprland/hyprland-gcc15-designated-initializer-fix-0.54.patch`
keeps affected Hyprland render-data initializers on assignment-based setup so
the local rounded-corner field does not trip designated-initializer ordering on
the current compiler.

Upstream has since absorbed most Hyprland 0.54 API porting in the plugin tree,
so the remaining active local plugin patches carry behavior deltas plus current
compatibility workarounds. `system/configuration.nix` still takes `hyprbars`
from `inputs.hyprland-plugins.packages.${system}.hyprbars`, but `hyprexpo` is
now supplied by the repo-local package in
`pkgs/hyprland-plugins/hyprexpo/default.nix` because the official plugin flake
no longer exposes that package. That local package extracts the last known
Hyprexpo source from upstream revision
`22de29bc1cf4126202df52691d0bc9a065089cba` and applies the existing local patch
against the patched Hyprland headers.

`patches/hyprland-plugins/hyprbars-hyprland-0.54.patch`
keeps `hyprbars` on the legacy `HyprlandAPI::addConfigValue(...)` plus
`HyprlandAPI::getConfigValue(...)` path, parses color strings through
`Config::ParserUtils::parseColor(...)`, renders the bar background with top-only
rounded corners, and opts the custom bar pass out of render-pass simplification.
`patches/hyprland-plugins/hyprexpo-hyprland-0.54.patch` carries the local
overview behavior: it debounces accidental select events immediately after
opening the overview, guards stale `startedOn` workspace checks with
`valid(startedOn)`, and lets `Config::Actions::changeWorkspace(...)` own the
workspace transition without duplicating desktop-animation calls.

Monitor behavior follows the same host split as inputs:

- The laptop pins the BenQ ZOWIE external display by EDID description at
  `1920x1080@120.00` on `0x0`, leaves `eDP-1` on `auto` placement so it becomes
  secondary when that external display is present and falls back to the origin
  when it is not, and keeps a fallback `monitor = , preferred, auto, 1` rule for
  everything else. `hosts/laptop/monitors.conf` also pins workspaces 1-10 to
  `desc:BNQ ZOWIE XL LCD EB12M01465SL0` when that monitor exists; Hyprland still
  gives every enabled output an active workspace, but the numbered workspace set
  stays on the external display instead of being assigned to the laptop panel.
  `desktopctl hypr lid-switch` supplements this static layout at runtime by
  disabling `eDP-1` on lid close only when a non-`eDP-1` output is active, which
  removes the hidden panel from the pointer/workspace layout while lid handling
  is inhibited.
- The desktop pins `HDMI-A-1` and keeps the same catch-all fallback.

Desktop-specific NVIDIA environment and resume quirks live in
`docs/nvidia/QUIRKS.md`.
