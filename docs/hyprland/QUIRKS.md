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

## Hyprland theme fragments are generated, not committed

**Symptom:** After a fresh clone or before the theming pipeline has run,
`hyprland.conf` and `appearance.conf` source generated theme fragments that do
not exist yet.

**Cause:** `cursor.conf`, `colors.conf`, and `appearance-theme.conf` are
generated at runtime by the theming pipeline's `cursor`, `hyprland`, and
`hypr_appearance` targets. They are not present in `config/hypr/` and are not
deployed by Home Manager's `xdg.configFile` declarations.

**Impact:** Hyprland logs a source-file-not-found warning on first boot before
the theming pipeline runs. The `home.activation.applyTheme` hook runs
`desktopctl theme sync` during Home Manager activation, which generates the
file before the first Hyprland session in normal use. A manual
`desktopctl theme` run is needed if the activation hook is skipped.

## Host-selected fragments must be tracked before rebuilding

**Symptom:** `hyprctl configerrors` reports a host-selected source such as
`~/.config/hypr/autostart-host.conf` as inaccessible even though the file exists
in the working tree.

**Cause:** The flake source used by `nixos-rebuild` only materializes files known
to Git. A newly added host fragment that is still untracked is omitted from the
store `self` source, so Home Manager can create a symlink to a path that does not
exist inside the materialized source tree.

**Impact / workaround:** After adding a new host-selected fragment under
`hosts/*/`, make sure the file is tracked by Git before rebuilding or activating
Home Manager. If the live symlink is already broken, rebuild/activate Home
Manager again after tracking the file.

## input-runtime.conf only overrides shared defaults

**Symptom:** The Mouse page's shared "Mouse Speed" setting changes, but a
specific mouse still keeps its old per-device feel.

**Cause:** `desktopctl hypr input set ...` writes
`~/.config/hypr/input-runtime.conf`, which is sourced after
`input-devices.conf` in `config/hypr/hyprland.conf`. That updates the
shared `input { ... }` defaults, but device-specific `device { ... }`
overrides such as the host-specific Logitech sensitivity blocks still apply
separately in `hosts/*/input-devices.conf`.

**Impact / workaround:** Use the Mouse page for the shared Hyprland defaults
that should apply when no device-specific override exists. Keep hardware-
specific tuning in `hosts/*/input-devices.conf`; those Logitech blocks still win
over the shared runtime value on hosts that define them.

## input-devices.conf is sourced before plugin keywords are available

**Symptom:** A plugin-owned gesture or dispatcher keyword can raise an
unknown-keyword error if placed in `hosts/laptop/input-devices.conf`.

**Cause:** `config/hypr/hyprland.conf` sources
`~/.config/hypr/input-devices.conf` before `~/.config/hypr/plugins.conf`.
Hyprland's `hyprlang` parser handles the config linearly and explicitly calls
out that plugin-owned keywords may need `# hyprlang noerror true` if they
appear before the plugin is loaded. The laptop fragment is therefore limited
to core Hyprland keywords even when it needs to trigger plugin behavior.

**Impact / workaround:** For laptop touchpad gestures that should toggle the
workspace overview, keep the binding on the core `gesture` keyword and use the
`dispatcher` action to call `hyprexpo:expo toggle` from
`hosts/laptop/input-devices.conf`. Reserve plugin-owned gesture keywords for
files sourced after `plugins.conf`, or guard them with `hyprlang noerror`.

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

## Rolling Hyprland inputs can make local patches fail during build

**Symptom:** `nrs` fails while building `hyprland` or a Hyprland plugin with
messages such as `Hunk #... FAILED`, `Reversed (or previously applied) patch
detected` during `patchPhase`, or compile errors in a locally patched plugin.

**Cause:** `system/configuration.nix` intentionally appends repo-local patches
to Hyprland, `hyprbars`, and `hyprexpo`. Upstream Hyprland and plugin inputs are
rolling flake inputs, so upstream may reformat touched code, remove fields, or
absorb parts of a local patch before the local patch stack is refreshed.

**Impact / workaround:** Refresh the relevant file under `patches/hyprland/` or
`patches/hyprland-plugins/` against the locked source revision, and prefer
dropping hunks that upstream has already absorbed instead of preserving stale API
porting context. Rebuild the patched Hyprland package and plugin stack before
running a full system rebuild, because the full desktop closure may also rebuild
the native kernel/NVIDIA stack.

## Hyprbars color parsing follows Hyprland parser utils on 0.55

**Symptom:** `nrs` fails while building `hyprbars` with
`error: 'configStringToInt' was not declared in this scope` from
`hyprbars/main.cpp` or `hyprbars/barDeco.cpp`.

**Cause:** Hyprland 0.55 removed the old unqualified color parsing helper that
the upstream `hyprbars` source still references. The current Hyprland headers
expose color parsing through `Config::ParserUtils::parseColor(...)` instead.

**Status:** Fixed in
`patches/hyprland-plugins/hyprbars-hyprland-0.54.patch`.

**Impact / workaround:** Keep the local `hyprbars/main.cpp` and
`hyprbars/barDeco.cpp` hunks on `Config::ParserUtils::parseColor(...)` while the
plugin stack remains pinned to a Hyprland 0.55 input. Re-check the patch when
upstream `hyprland-plugins` absorbs the same parser API change.

## Official hyprland-plugins no longer ships Hyprexpo

**Symptom:** `nrs` fails during evaluation with `attribute 'hyprexpo' missing`
from `system/configuration.nix`.

**Cause:** The official `hyprwm/hyprland-plugins` flake removed `hyprexpo` from
its package set. The repo previously built the overview plugin from
`inputs.hyprland-plugins.packages.${system}.hyprexpo`, so a lockfile update can
break evaluation before Nix reaches the build phase.

**Status:** Workaround in place. Keep `flake.lock` pinned to the
`hyprland-plugins` revision `22de29bc1cf4126202df52691d0bc9a065089cba`, the
last known input revision in this repo that still exposes `hyprexpo`, unless the
overview config is intentionally migrated away from Hyprexpo.
