# Hyprland Quirks

## Shared brightness hooks assume a discoverable backlight device

**Symptom:** Brightness controls do nothing useful on the desktop or a future
host with no `/sys/class/backlight` device.

**Cause:** The shared Hyprland surfaces all route through `desktopctl
brightness`, which auto-detects the first backlight under
`/sys/class/backlight/` and errors when none exists:

Specifically:

- `config/hypr/hypridle.conf` listener block with `on-timeout = desktopctl brightness dim` and `on-resume = ... desktopctl brightness restore`
- `config/hypr/keybinds.conf` brightness bindings for `F6` / `F7` that call `desktopctl brightness down` and `desktopctl brightness up`

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

## Ableton Live 12 Lite must float under the current Wine Wayland path

**Symptom:** When Ableton Live 12 Lite runs through Wine's Wayland driver on the
desktop host, a tiled Hyprland layout leaves parts of the lower UI clipped and
some internal panes stop resizing correctly.

**Cause:** The current Wine Wayland path does update swapchain sizes, but the
Ableton window still behaves poorly when Hyprland keeps it tiled across the full
workspace. Floating avoids the compositor/layout interaction that leaves the UI
partially cut off.

**Impact / workaround:** `config/hypr/rules.conf` floats and centers windows
whose class is `ableton live 12 lite.exe` and also floats the fixed-size Wine
virtual desktop host window `explorer.exe` titled `Ableton - Wine Desktop`.
Keep Ableton floating for now instead of relying on Hyprland tiling.
