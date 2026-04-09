# Hyprland Quirks

## Shared brightness hooks assume a discoverable backlight device

**Symptom:** Brightness controls do nothing useful on the desktop or a future
host with no `/sys/class/backlight` device.

**Cause:** The shared Hyprland surfaces all route through `desktopctl
brightness`, which auto-detects the first backlight under
`/sys/class/backlight/` and errors when none exists:

- `hypridle.conf:10-11` — dim-screen timeout and restore handler
- `keybinds.conf:62-63` — repeat-on-hold brightness step binds

These work on the laptop (which has a discoverable backlight device) but fail
on the desktop (dedicated NVIDIA, no backlight device).

**Impact:** On the desktop, the dim-screen timeout has no visible effect and
the brightness keybinds do nothing. No crashes, but the brightness-related
shared surfaces remain laptop-oriented.

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
`input-devices.conf` (`config/hypr/hyprland.conf:7-12`). That updates the
shared `input { ... }` defaults, but device-specific `device { ... }`
overrides such as the desktop's Logitech sensitivity blocks still apply
separately (`hosts/desktop/input-devices.conf:3-9`).

**Impact / workaround:** Use the Mouse page for the shared Hyprland defaults
that should apply when no device-specific override exists. Keep hardware-
specific tuning in `hosts/*/input-devices.conf`; on the desktop, those Logitech
blocks still win over the shared runtime value.

## input-devices.conf is sourced before plugin keywords are available

**Symptom:** A plugin-specific gesture keyword such as `hyprexpo-gesture`
would raise an unknown-keyword error if placed in
`hosts/laptop/input-devices.conf`.

**Cause:** `config/hypr/hyprland.conf:5-10` sources
`~/.config/hypr/input-devices.conf` before `~/.config/hypr/plugins.conf`.
Hyprland's `hyprlang` parser handles the config linearly and explicitly calls
out that plugin-owned keywords may need `# hyprlang noerror true` if they
appear before the plugin is loaded. The laptop fragment is therefore limited
to core Hyprland keywords even when it needs to trigger plugin behavior.

**Impact / workaround:** For laptop touchpad gestures that should toggle the
workspace overview, keep the binding on the core `gesture` keyword and use the
`dispatcher` action to call `hyprexpo:expo toggle`
(`hosts/laptop/input-devices.conf:10-11`). Reserve `hyprexpo-gesture` for files
sourced after `plugins.conf`, or guard it with `hyprlang noerror`.
