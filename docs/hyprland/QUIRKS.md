# Hyprland Quirks

## Enabled outputs always have an active workspace

**Symptom:** A connected laptop panel cannot behave as a literal workspace-less
extension of the external monitor.

**Cause:** Hyprland's workspace model attaches an active workspace to every
enabled monitor. A monitor can be placed next to another monitor, mirrored, or
disabled, but it cannot remain enabled with no workspace at all.

**Status:** By design, with laptop-host workarounds.

**Impact / workaround:** `hosts/laptop/monitors.conf` pins workspaces 1-10 to the
BenQ ZOWIE external monitor by EDID description when it is attached. The internal
`eDP-1` output remains enabled and spatially adjacent while the lid is open, but
any workspace Hyprland parks there is outside the normal numbered workspace set.
When the lid closes while another output is active, `hosts/laptop/input-devices.conf`
switch binds call `desktopctl hypr lid-switch closed --internal eDP-1`, which
disables the hidden panel so it no longer exists as a pointer-crossable area.

## MX Master 2S smart-shift is capped at 50 in Solaar CLI

**Symptom:** `solaar config "MX Master 2S" smart-shift 100` fails with
`smart-shift: value '100' out of bounds`.

**Cause:** For this device, Solaar exposes `smart-shift` on a 0-50 scale and
documents `50` as the always-ratcheted value.

**Impact / workaround:** Keep `hosts/laptop/autostart.conf` on
`scroll-ratchet Ratcheted` plus `smart-shift 50` for the strongest supported
ratcheted behavior instead of leaving a failing startup command.
`hosts/desktop/autostart.conf` applies only the `smart-shift 50` command with
no scroll-ratchet line; that asymmetry is the current deliberate state (owner
question pending).

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

## Portal services need the imported graphical-session environment

**Symptom:** Browser file pickers can fail to appear on a fresh Hyprland login even though the same portal services look healthy after they have been restarted later in the session.

**Cause:** XDG portal backends are user services that need the Hyprland session environment, especially `WAYLAND_DISPLAY`, `XDG_CURRENT_DESKTOP`, and the profile paths exported by the NixOS/Home Manager session. If they are activated before that environment is imported into D-Bus and the user manager, the first portal instance can start with incomplete context. Leaving `graphical-session.target` inactive also makes activation timing depend on whichever app touches the portal first.

**Status:** Fixed in `config/hypr/autostart.conf`.

**Impact / workaround:** Keep the environment import, token scrub, `graphical-session.target` start, and explicit XDG portal service start in the first shared `exec-once` command. `exec-shutdown` stops `graphical-session.target` so PartOf-bound user services do not outlive the compositor session.

## Shared brightness hooks list backlight and DDC/CI devices

**Symptom:** Older checkouts had brightness controls that did nothing useful on
the desktop or a future host with no `/sys/class/backlight` device.

**Cause:** The shared Hyprland surfaces all route through `desktopctl
brightness`. Current code lists readable backlights under `/sys/class/backlight/`
and DDC/CI VCP `0x10` displays detected through `ddcutil detect --brief`, while
keyboard step/dim commands still use the first backlight before falling back to
DDC/CI when no backlight exists:

Specifically:

- `config/hypr/hypridle.conf` listener block with `on-timeout = desktopctl brightness dim` and `on-resume = ... desktopctl brightness restore`
- `config/hypr/keybinds.conf` brightness bindings for `F6` / `F7` that call `desktopctl brightness down` and `desktopctl brightness up`

These work on the laptop through the internal backlight and on DDC/CI-capable
external monitors when the host has I2C access. Quickshell filters the internal
backlight slider out when no enabled `eDP`/`LVDS`/`DSI` monitor is present, so a
closed-lid external-monitor session shows only the DDC/CI sliders that are still
visible.

**Status:** Fixed for DDC/CI-capable monitors.

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
`config/hypr/keybinds.conf` is sourced after `plugins.conf`, so it binds
SUPER+grave to the `hyprexpo:expo` dispatcher directly; the dispatcher-action
indirection remains required only for files sourced before `plugins.conf`,
such as `hosts/laptop/input-devices.conf`.

## hyprpolkitagent sets no app_id, so its window rule matches by title

**Symptom:** A class-based window rule for the polkit prompt
(`hyprland-polkitagent` or similar) never matches; the agent window reports an
empty class in `hyprctl clients`.

**Cause:** hyprpolkitagent v0.1.3 (Qt, Nix-wrapped) sets no app_id, so its
Wayland class is empty. The window title comes from Qt
`setApplicationName("Hyprland Polkit Agent")`.

**Status:** Fixed in `config/hypr/rules.conf`.

**Impact / workaround:** The rule is now `windowrule = match:title Hyprland
Polkit Agent, float on, center on`. The title may drift with upstream
hyprpolkitagent updates — same re-check caveat as other class/title-drift
rules: verify with `hyprctl clients` while the prompt is open after bumping the
package.

## hyprlock enables fingerprint auth on every host, including hosts without fprintd

**Symptom:** On the desktop, hyprlock logs a D-Bus error about fprintd at
unlock time even though unlocking works fine with the password.

**Cause:** The shared `config/hypr/hyprlock.conf` enables
`auth { fingerprint { enabled = true } }` on every host, while only
`hosts/laptop/system.nix` configures `services.fprintd`. On hosts without
fprintd the D-Bus call fails and hyprlock silently degrades to password-only
auth.

**Status:** Documented fallback, deliberate.

**Impact / workaround:** This is the documented fallback satisfying the SPEC
static-base constraint ("Static files must not contain host-specific hardware
assumptions unless guarded by a documented fallback"). A host config split is
deliberately not done; treat the desktop's fprintd D-Bus error as noise.

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

**Impact / workaround:** `patches/hyprland-plugins/hyprbars-hyprland-0.55.patch`
now refreshes the current rendering hunks and also moves `hyprbars` back to the
legacy plugin-config path used by the other working plugins on this stack:
`hyprbars/main.cpp` registers defaults through
`HyprlandAPI::addConfigValue(...)`, while `hyprbars/globals.hpp` and the render
code read live values through `HyprlandAPI::getConfigValue(...)` instead of the
crashing `addConfigValueV2(...)` / `Config::Values::*Value` path. New upstream
plugin settings such as `bar_text_weight` still need matching legacy defaults and
`HyprbarsConfig` helpers when this patch is refreshed. Re-test `hyprbars` against
future input bumps before dropping that local workaround.

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
porting context. The current Hyprland 0.55 lock required refreshing
`patches/hyprland/hyprland-floating-top-decoration-rounding-0.55.patch` for the
relocated `Window.hpp` method block, the reformatted shader-feature enum, and
surface rounding calls now guarded by `!USE_MOTION_BLUR`, while dropping a stale
no-newline hunk. The companion
`patches/hyprland/hyprland-gcc15-designated-initializer-fix-0.55.patch` must
preserve newer texture fields such as `wrapX`, `wrapY`, `forceBlurBlend`,
`blurAlphaMatte`, and `motionBlur` when rewriting designated initializers to
assignment-based setup; the matching `hyprbars` plugin refresh also had to carry
upstream `bar_text_weight` through the legacy config helper stack. The current
June 2026 Hyprland 0.55 lock also required dropping a stale `hyprbars`
plugin-exit monitor-iteration hunk that the locked upstream plugin source already
absorbed, and refreshing the repo-local `hyprexpo` patch for the
`Monitor::CMonitor` namespace, `output/Monitor.hpp`, the renamed monitor damage
hook symbol, `State::workspaceState()->query().id(...).run()` workspace lookup,
and `CMonitor::scheduleFrame()` monitor frame scheduling.
Rebuild the patched Hyprland package and plugin stack before running a full
system rebuild, because the full desktop closure may also rebuild the system
kernel/NVIDIA stack.

## Hyprbars color parsing follows Hyprland parser utils on 0.55

**Symptom:** `nrs` fails while building `hyprbars` with
`error: 'configStringToInt' was not declared in this scope` from
`hyprbars/main.cpp` or `hyprbars/barDeco.cpp`.

**Cause:** Hyprland 0.55 removed the old unqualified color parsing helper that
the upstream `hyprbars` source still references. The current Hyprland headers
expose color parsing through `Config::ParserUtils::parseColor(...)` instead.

**Status:** Absorbed upstream. The locked `hyprland-plugins` input (rev
`8c3d2be`) already includes the ParserUtils include and uses
`Config::ParserUtils::parseColor`, and the local
`patches/hyprland-plugins/hyprbars-hyprland-0.55.patch` no longer carries any
parseColor hunks (removed in commit `b74af9e`).

**Impact / workaround:** Nothing to maintain locally; re-check only when the
`hyprland-plugins` input is bumped, in case upstream and the Hyprland parser
API diverge again.

## Official hyprland-plugins no longer ships Hyprexpo

**Symptom:** `nrs` fails during evaluation with `attribute 'hyprexpo' missing`
from `system/configuration.nix`.

**Cause:** The official `hyprwm/hyprland-plugins` flake removed `hyprexpo` from
its package set. The repo previously built the overview plugin from
`inputs.hyprland-plugins.packages.${system}.hyprexpo`, so a lockfile update can
break evaluation before Nix reaches the build phase.

**Status:** Workaround in place. `system/configuration.nix` now wires
`hyprexpo` from `pkgs/hyprland-plugins/hyprexpo/default.nix`, a repo-local
package that extracts the removed plugin source from upstream revision
`eaf18d55d51cef00818c5a4fdd4170f8cc2de4dc` and applies
`patches/hyprland-plugins/hyprexpo-hyprland-0.55.patch`. The main
`hyprland-plugins` flake input can keep rolling for still-shipped plugins such
as `hyprbars`; Hyprexpo maintenance now means refreshing the local package or
patch when Hyprland headers change.
