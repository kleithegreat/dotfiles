# TODO

Open issues and pending validations. Delete entries when resolved.

## Pending validation (needs real hardware / live session)

- [ ] Session restore on demand: turn "Restore windows at login" off,
      reboot, and confirm nothing reopens and the power menu offers "Restore
      Windows" once.
- [ ] Quickshell, what a screenshot could not prove: OSD suppression across
      a volume drag; night-light commit-on-release; Wi-Fi join forms
      including enterprise; Display staged apply and its revert countdown;
      tray menus.
- [ ] Laptop Bluetooth, after the rebuild: the adapter should be off at
      boot; turn it on from the Control Center tile, pair something in
      Settings → Bluetooth, and confirm audio routes to it. The shell's
      native adapter path has never run against a real bluez.
- [ ] Log out without rebooting and confirm `desktopctl.service` stops with
      the session.
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

- [ ] macOS VM: `nvidia-offload macos-vm run` on the laptop boots the
      installed Ventura guest to a rendered desktop on the 3050. Still
      unchecked: the desktop host (the device's Vulkan window there),
      `--console` showing OpenCore, and `fetch` → `install` from nothing
      with the current package. See `docs/macos-vm.md`.

## Open issues

- [ ] Nix (low): `pkgs/reims-vgpu` still has `sed -i` in its build script;
      changing it means rebuilding the QEMU fork to prove the script.
- [ ] Nix (low): the patched Discord builds, but nobody has checked that the
      `postInstall` replacing `discord_krisp` lands in what the FHS wrapper
      actually runs.
- [ ] desktopctl (low): `resolve_place_name` rewrites the location cache on
      a pinned host too, which `docs/sun-schedule.md` says never happens. The
      result is still treated as stale, so nothing breaks; the doc or the
      write should change.
- [ ] Hyprland (low): the Bitwarden popup rule matches
      `chrome-nngceckbapebfimnlniiiahkandclblb-Default`; check with
      `hyprctl clients` that Helium really gives the popup that class.
