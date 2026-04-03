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

## intel_backlight assumptions in shared config

**Symptom:** Brightness controls fail silently on the desktop or a future host
without an Intel backlight device.

**Cause:** Three shared config files hardcode `intel_backlight` as the
backlight device:

- `autostart.conf:6` — initial brightness snapshot for Quickshell
- `hypridle.conf:10-11` — dim-screen timeout and resume handler
- `keybinds.conf:62-63` — brightness step binds (via `desktopctl brightness`)

These work on the laptop (Intel Iris Xe iGPU) but are no-ops or errors on the
desktop (dedicated NVIDIA, no Intel backlight).

**Impact:** On the desktop, the brightness snapshot writes nothing useful, the
dim-screen timeout fires but has no effect, and the brightness keybinds do
nothing. No crashes, but the idle dim behavior is silently broken.

## Inactive config fragments in the source tree

**Symptom:** Reading the `config/hypr/` directory suggests more active files
than the compositor actually loads.

**Fragments:**

- `pluginsettings.conf` — superseded by `plugins.conf`, which now contains both
  plugin loading and plugin settings. Not sourced by `hyprland.conf`.
- `config/hypr/monitors.conf` — exists as a template with laptop-oriented
  defaults, but all known hosts use host-specific monitor files instead. The
  fallback branch in `home/default.nix` inlines the generic monitor rule rather
  than sourcing this file.

**Why it matters:** When modifying plugin settings, editing `pluginsettings.conf`
instead of `plugins.conf` will have no effect. Similarly, editing
`config/hypr/monitors.conf` will not change monitor behavior on any known host.

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
