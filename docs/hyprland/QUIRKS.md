# Hyprland Quirks

## D-Bus-activated windows can inherit stale workspace tokens

**Symptom:** Portal file pickers, keyring prompts, and some D-Bus-activatable
apps can open on workspace 1 even when requested from another workspace. Apps
such as Nautilus may only show this on first launch because later windows are
created by the already-running app process.

**Cause:** Hyprland injects `HL_INITIAL_WORKSPACE_TOKEN` into `exec` /
`exec-once` child environments for initial workspace tracking. If session startup
copies the entire `exec-once` environment into D-Bus/systemd activation, or if a
long-lived autostart daemon such as an app launcher keeps that token in its own
environment, future windows launched through that helper inherit the startup
workspace token and Hyprland places them on that workspace.

**Status:** Fixed in `config/hypr/autostart.conf`.

**Impact / workaround:** Keep `HL_INITIAL_WORKSPACE_TOKEN`,
`XDG_ACTIVATION_TOKEN`, and `DESKTOP_STARTUP_ID` out of the D-Bus/systemd
activation environment and out of long-lived autostart daemons. If the bug
appears in an already-running session, clear those variables from the user
manager and restart affected D-Bus helpers or app-launcher daemons, or log out
and back in after rebuilding the config.

## Shared brightness hooks use backlight first, then DDC/CI

**Symptom:** Older checkouts had brightness controls that did nothing useful on
the desktop or a future host with no `/sys/class/backlight` device.

**Cause:** The shared Hyprland surfaces all route through `desktopctl
brightness`. Current code auto-detects the first backlight under
`/sys/class/backlight/`, then falls back to DDC/CI VCP `0x10` through
`ddcutil` when no backlight exists:

Specifically:

- `config/hypr/hypridle.conf` listener block with `on-timeout = desktopctl brightness dim` and `on-resume = ... desktopctl brightness restore`
- `config/hypr/keybinds.conf` brightness bindings for `F6` / `F7` that call `desktopctl brightness down` and `desktopctl brightness up`

These work on the laptop through the internal backlight and on the desktop when
the external monitor exposes DDC/CI brightness and the host has I2C access.

**Status:** Fixed for DDC/CI-capable desktop monitors.

**Impact / workaround:** If a desktop monitor still does not respond, verify the
monitor OSD has DDC/CI enabled, `ddcutil detect` can see the display, and the
active user is in the `i2c` group after a rebuild and fresh login.

## cursor.conf is generated, not committed

**Symptom:** After a fresh clone or before the theming pipeline has run,
`hyprland.conf` sources `~/.config/hypr/cursor.conf` which does not exist yet.

**Cause:** `cursor.conf` is generated at runtime by the theming pipeline's
`cursor` target. It is not present in `config/hypr/` and is not deployed by
Home Manager's `xdg.configFile` declarations.

**Impact:** Hyprland logs a source-file-not-found warning on first boot before
the theming pipeline runs. The `home.activation.applyTheme` hook runs
`desktopctl theme sync` during Home Manager activation, which generates the
file before the first Hyprland session in normal use. A manual
`desktopctl theme` run is needed if the activation hook is skipped.

## input-runtime.conf only overrides shared defaults

**Symptom:** The Mouse page's shared "Mouse Speed" setting changes, but a
specific mouse still keeps its old per-device feel.

**Cause:** `desktopctl hypr input set ...` writes
`~/.config/hypr/input-runtime.conf`, which is sourced after
`input-devices.conf` in `config/hypr/hyprland.conf`. That updates the
shared `input { ... }` defaults, but device-specific `device { ... }`
overrides such as the desktop's Logitech sensitivity blocks still apply
separately in `hosts/desktop/input-devices.conf`.

**Impact / workaround:** Use the Mouse page for the shared Hyprland defaults
that should apply when no device-specific override exists. Keep hardware-
specific tuning in `hosts/*/input-devices.conf`; on the desktop, those Logitech
blocks still win over the shared runtime value.

## input-devices.conf is sourced before plugin keywords are available

**Symptom:** A plugin-specific gesture keyword such as `hyprexpo-gesture`
would raise an unknown-keyword error if placed in
`hosts/laptop/input-devices.conf`.

**Cause:** `config/hypr/hyprland.conf` sources
`~/.config/hypr/input-devices.conf` before `~/.config/hypr/plugins.conf`.
Hyprland's `hyprlang` parser handles the config linearly and explicitly calls
out that plugin-owned keywords may need `# hyprlang noerror true` if they
appear before the plugin is loaded. The laptop fragment is therefore limited
to core Hyprland keywords even when it needs to trigger plugin behavior.

**Impact / workaround:** For laptop touchpad gestures that should toggle the
workspace overview, keep the binding on the core `gesture` keyword and use the
`dispatcher` action to call `hyprexpo:expo toggle`
from `hosts/laptop/input-devices.conf`. Reserve `hyprexpo-gesture` for files
sourced after `plugins.conf`, or guard it with `hyprlang noerror`.

## Rolling Hyprland input bumps can break the patched plugin stack at login

**Symptom:** SDDM accepts the password, then immediately returns to the greeter
because Hyprland aborts during session startup.

**Cause:** On the 2026-04-29 Hyprland input bump (`45ffaee...`) the compositor
started aborting while loading `libhyprbars.so`, before the session became
interactive. The journal showed repeated `pluginInit (libhyprbars.so)` crashes
through `Config::Values::*Value::commence()` during
`HyprlandAPI::addConfigValueV2(...)`, so the failure was in the local
`hyprbars` plugin-config registration path rather than PAM, SDDM, or the
GPU-routing env.

**Impact / workaround:** `patches/hyprland-plugins/hyprbars-hyprland-0.54.patch`
now refreshes the current rendering hunks and also moves `hyprbars` back to the
legacy plugin-config path used by the other working plugins on this stack:
`hyprbars/main.cpp` registers defaults through
`HyprlandAPI::addConfigValue(...)`, while `hyprbars/globals.hpp` and the render
code read live values through `HyprlandAPI::getConfigValue(...)` instead of the
crashing `addConfigValueV2(...)` / `Config::Values::*Value` path. Re-test
`hyprbars` against future input bumps before dropping that local workaround.

## Hyprbars needs pass simplification disabled for Hyprexpo captures

**Symptom:** Floating windows render with `hyprbars` in the normal workspace, but
their title bars disappear from the `hyprexpo` overview tiles.

**Cause:** `hyprexpo` captures each workspace through Hyprland's fake render
path. In Hyprland 0.54, render-pass simplification walks elements in reverse and
can let later opaque window surfaces drain the damage region before the
under-window `hyprbars` decoration pass is reached. Returning no bounding box is
not sufficient because the element can still receive empty damage.

**Status:** Fixed in
`patches/hyprland-plugins/hyprbars-hyprland-0.54.patch` by adding
`CBarPassElement::disableSimplification()` and keeping a real bounding box for
blur/debug bookkeeping. Re-check this patch when Hyprland changes pass
simplification or when upstream `hyprbars` changes its decoration layer.

## Hyprexpo empty workspace clicks need the action path

**Symptom:** From the Hyprexpo overview, clicking a tile for a workspace with no
active applications closes the overview but lands back on the workspace where
Hyprexpo was launched.

**Cause:** Current Hyprland keeps workspace creation in the action/dispatcher
path. `CMonitor::changeWorkspace(WORKSPACEID)` only resolves an existing
workspace and returns without switching when `g_pCompositor->getWorkspaceByID`
returns null. Hyprexpo's overview tiles can represent not-yet-created empty
workspaces, so calling that monitor overload makes empty-tile selection a no-op.

**Status:** Fixed in
`patches/hyprland-plugins/hyprexpo-hyprland-0.54.patch` by calling
`Config::Actions::changeWorkspace(...)` for both existing and missing target
workspace IDs. That keeps the current Hyprland creation, focus, event, and
animation behavior instead of duplicating it in the plugin patch.
