# TODO

Open issues and pending validations. Delete entries when resolved.

## Pending validation (needs real hardware / live session)

- [ ] Desktop suspend/resume: validate the post-overlay-removal resume stack
      (see `docs/nvidia.md`). Until a real cycle passes, keep
      `kernelSuspendNotifier = false`, the `/var/tmp` VRAM path, and the
      sleep-freeze workaround.
- [ ] Displays subsystem, multi-monitor half (needs an external display
      attached): plug and unplug one and confirm the wallpaper lands on it,
      the bar and every surface move to it, and workspaces 1-10 follow — then
      that unplugging hands all three back to the built-in panel. Toggle
      "Main display" onto the internal panel with an external attached and
      confirm that choice survives a relogin, and that a *different* unknown
      monitor still auto-selects. Drag a display in the arrangement canvas and
      check the edge snap and the countdown's revert with two outputs.

- [ ] Quickshell live smoke test after the rewrite (needs hands on the UI):
      slider drags end to end (OSD suppression across a volume drag,
      night-light commit-on-release, brightness drag vs pushed events), Wi-Fi
      join forms including enterprise, Display staged apply and its revert
      countdown, tray menus via QsMenuOpener, and the Bluetooth pane on the
      laptop — the desktop has no bluez running, so the native adapter path is
      untested on real hardware. Daemon-pushed state, same session: terminal
      `desktopctl theme set color_scheme` updates an open settings pane;
      brightness slider tracks Super+F6/F7 and the OSD appears; Super+F8
      updates the night-light tile promptly; a manual `dark_hint` is
      reasserted by the schedule at the next 23:00/06:00 edge.
- [ ] After the next rebuild: `systemctl --user restart desktopctl` and
      confirm the shell resubscribes (`ss -x | grep desktopctl.sock` shows a
      connection again within a second or two, and a settings pane tracks a
      terminal `theme set`) — the recreate-the-Socket reconnect was proven
      only in a throwaway Quickshell instance. Leave the laptop idle 5 minutes
      and confirm the screen dims and restores. Log out without rebooting and
      confirm `desktopctl.service` stops with the session.

- [ ] Session restore, end to end (needs a rebuild and a relogin; only the
      recorder, the placement dispatchers and the unit tests have run): with
      a terminal in some project directory, two Helium windows and VS Code
      spread over workspaces, reboot and confirm each comes back on its
      workspace and the terminal in its directory. Turn "Restore windows at
      login" off in Settings → Window, reboot, confirm nothing reopens and the
      power menu offers "Restore Windows" once. Check Helium really reopens
      its windows when launched bare, and that `desktopctl session status`
      reports `restorable = 0` after either path.

- [ ] macOS VM, end to end (needs a guest install): nothing in it has been
      booted. `macos-vm fetch` → `install` → `run`, then check that the
      reims-vgpu device's own Vulkan window opens on the desktop, that
      `nvidia-offload macos-vm run` on the laptop reaches the 3050 rather than
      Intel's ANV, and that `--console` still shows OpenCore. The package has
      only been built on the desktop; the laptop has not compiled it yet.
      See `docs/macos-vm.md`.

## Open issues

- [ ] NVIDIA (high): laptop `AQ_DRM_DEVICES` depends on hardcoded
      `/dev/dri/cardN` ordering. Add a udev rule giving the two GPUs
      colon-free symlinks and list those instead (see docs/nvidia.md). Needs
      a relogin to validate, and a wrong rule means no session.
- [ ] Nix (low): the NVIDIA/CUDA entries in `allowedUnfreePackageNames` have
      no per-entry reason or host annotation, making cleanup triage harder.

- [ ] Quickshell (medium): the Pointer pane's "Scrolling" slider writes
      `input:scroll_factor`, which the touchpad ignores — the laptop's
      `input:touchpad:scroll_factor` (0.25, in `hosts/laptop/input-devices.lua`)
      is not reachable from any UI. Scroll speed inside the shell is now
      consistent between panes and option strips, but if it still feels slow,
      that hardcoded 0.25 is the knob and it wants a home in
      `input-defaults.lua` with the rest.

- [ ] GeoClue (medium): the IP source is disabled on both hosts (`Unknown IP
      source method '(null)'`). The laptop still gets a fix — `where-am-i`
      answers through the WiFi source's IP fallback, 25 km accuracy — which is
      enough for `automatic-timezoned` and sun-schedule; the desktop resolves
      nothing real and pins `time.timeZone` and `DESKTOPCTL_LOCATION` instead.
      Either give GeoClue a working IP source or drop it for static
      coordinates on the laptop too; if it goes, the laptop needs a different
      timezone story and `location.provider`, `services.geoclue2`, and the
      `where-am-i` path in `docs/sun-schedule.md` go with it.
- [ ] desktopctl (low): the daemon logs `wallpaper warning: failed to apply
      wallpaper ...: "none of the requested outputs are valid"` once at every
      start. The autostart apply lands the wallpaper regardless, so this is
      the daemon applying before awww knows its outputs — find which startup
      path does it and either wait or drop the redundant apply.
