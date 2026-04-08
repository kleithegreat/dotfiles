# Hyprland Quirks

## Unstable /dev/dri/cardN paths in AQ_DRM_DEVICES

**Symptom:** After a kernel update or driver change on the laptop, Hyprland can
start on the wrong GPU or fail to initialize the intended Intel-primary
ordering.

**Cause:** `config/hypr/env.conf:15` sets
`AQ_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1` using hardcoded card numbers.
The Linux kernel does not guarantee stable `/dev/dri/cardN` assignment across
boots — the numbering depends on driver probe order, which can shift with
kernel updates, module load ordering, or hardware changes.

**Current behavior:** The laptop depends on Intel Iris Xe probing as `card2`
and the NVIDIA dGPU probing as `card1`. If this ordering changes, the
compositor will either use the wrong GPU as primary or fail to start.

**Why it persists:** Hyprland's `AQ_DRM_DEVICES` only accepts `/dev/dri/cardN`
paths. Unlike `by-path` or `by-id` symlinks used elsewhere in Linux, there is
no stable-path alternative for DRM device selection in this variable.

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

## Desktop env.conf mixes environment and autostart

**Symptom:** `hosts/desktop/env.conf` contains an `exec-once` directive
alongside environment variables.

**Cause:** `hosts/desktop/env.conf:24` runs
`exec-once = solaar config "MX Master 2S" smart-shift 50` to configure the
Logitech mouse at session start. This is a host-specific autostart concern
placed in an environment fragment.

**Impact:** No functional issue — Hyprland processes both `env` and `exec-once`
regardless of file name. The concern is semantic: someone looking for autostart
commands might miss this one because it lives in the env fragment.
