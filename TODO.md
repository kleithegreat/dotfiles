# TODO

Open issues and pending validations. Delete entries when resolved.

## Pending validation (needs real hardware / live session)

- [ ] Laptop, FIRST login after the next rebuild: Hyprland now finds its GPUs
      through `/dev/dri/intel-gpu` and `/dev/dri/nvidia-gpu`, udev symlinks
      that have only been dry-run. If SDDM takes the password and bounces
      back, boot the previous generation and see `docs/nvidia.md`. Once in,
      `ls -l /dev/dri` should show both links.
- [ ] After the next rebuild and reboot, with Helium open beforehand: it
      should come back with its tabs instead of a blank window offering to
      restore. Then turn "Restore windows at login" off, reboot, and confirm
      nothing reopens and the power menu offers "Restore Windows" once.
- [ ] After the next rebuild, the fixes nothing here could exercise:
      `journalctl --user -b -u desktopctl` has no `wallpaper warning`;
      `journalctl -b -u geoclue` has no `Unknown IP source method`; night
      light switched off from the Control Center shows as off at once; the
      Pointer pane's "Touchpad scrolling" slider changes two-finger scroll
      speed; LTeX underlines a misspelling in a Markdown file (it was
      disabled outright until now — set it back if the noise is unwelcome).
- [ ] Laptop, after the rebuild: remove one fingerprint in Settings →
      Fingerprint and confirm no password prompt appears and the others
      survive; add one and confirm the card fills per touch on the real
      reader (it has only been driven by a fake `fprintd-enroll`).
- [ ] Quickshell, what a screenshot could not prove: wheel and touchpad
      scrolling in panes and option strips after the shared scroll engine
      (glide, overshoot, recoil); OSD suppression across a volume drag;
      night-light commit-on-release; Wi-Fi join forms including enterprise;
      Display staged apply and its revert countdown; tray menus.
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

- [ ] macOS VM, end to end (needs a guest install): nothing in it has been
      booted. `macos-vm fetch` → `install` → `run`, then check that the
      reims-vgpu device's own Vulkan window opens on the desktop, that
      `nvidia-offload macos-vm run` on the laptop reaches the 3050 rather than
      Intel's ANV, and that `--console` still shows OpenCore. The package has
      only been built on the desktop; the laptop has not compiled it yet.
      See `docs/macos-vm.md`.

## Open issues

- [ ] Quickshell (medium): the Bluetooth pane, tile and service have no host
      to run on — neither host enables `hardware.bluetooth`, so bluez is
      absent and the native adapter path has never run. Enable it on the
      laptop or delete the three.
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
