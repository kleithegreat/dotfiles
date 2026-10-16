# TODO

Open issues and pending validations. Delete entries when resolved.

## Pending validation (needs real hardware / live session)

- [ ] Session restore on demand: turn "Restore windows at login" off,
      reboot, and confirm nothing reopens and the power menu offers "Restore
      Windows" once.
- [ ] Quickshell, what a screenshot could not prove: no OSD while dragging
      the volume slider or right after letting go (it now ignores the shell's
      own volume writes for 400 ms); night-light commit-on-release; Wi-Fi join forms
      including enterprise; Display staged apply and its revert countdown;
      tray menus.
- [ ] Laptop Bluetooth: turn the adapter on from the Control Center tile,
      pair something in Settings → Bluetooth, and confirm audio routes to it.
      The shell's native adapter path has never run against a real bluez.
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

- [ ] macOS VM, after the move to upstream's `apple-gfx-pci` and its option
      ROM: `nvidia-offload macos-vm run` on the laptop boots the installed
      Ventura guest to a rendered desktop on the 3050, and OpenCore's picker
      now shows in the device's own window. Still unchecked: the Tahoe
      install in `~/vm/macos-tahoe` booted on the device, the desktop host,
      and `--console`. See `docs/macos-vm.md`.
- [ ] Laptop power-saver on battery (`docs/laptop-power.md`): compare idle
      package power and battery draw against the old `e-core-only` (before
      56c2f99); if lavd loses clearly, that is the case for bringing it back.
      `intel-rapl:0/energy_uj` is world-readable, so no turbostat or sudo is
      needed; `BAT0` has no `power_now`, so draw is `current_now` ×
      `voltage_now`.

- [ ] Under nftables: Tailscale, a podman container's network, and libvirt's
      default network all work.
- [ ] Laptop greeter startup: every real SDDM greeter start spends 1.4–2.5s
      between `High-DPI autoscaling Enabled` and loading `Main.qml`, even
      after a logout on an idle system; under a headless nested kwin it takes
      ~0.1s. Neither the dGPU nor boot contention explains it.

## Open issues

- [ ] Hyprland (low): the Bitwarden popup rule matches
      `chrome-nngceckbapebfimnlniiiahkandclblb-Default`; check with
      `hyprctl clients` that Helium really gives the popup that class.
