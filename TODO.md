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

- [ ] macOS VM on the desktop host, after the move to upstream's
      `apple-gfx-pci` and its option ROM (`docs/macos-vm.md`): boot a guest to
      a rendered desktop on the device, then the Tahoe install, then
      `--console`.
- [ ] Ableton Live on the desktop host (`docs/ableton-live.md`): only tested
      on the laptop at scale 1 on the iGPU. Run upstream's `setup-prefix`,
      install Live, and re-test click targeting on the RTX 3080.
- [ ] Laptop power-saver on battery (`docs/laptop-power.md`): compare idle
      package power and battery draw against the old `e-core-only` (before
      56c2f99); if lavd loses clearly, that is the case for bringing it back.
      `intel-rapl:0/energy_uj` is world-readable, so no turbostat or sudo is
      needed; `BAT0` has no `power_now`, so draw is `current_now` ×
      `voltage_now`.

- [ ] Laptop face auth: after `sudo linux-enable-ir-emitter configure`, add
      and remove a face from Settings → Authentication (pkexec, no prompt),
      then confirm `sudo` and hyprlock both unlock by face, and that
      hyprlock's PAM thread (running as the user, not root) can read
      `/var/lib/howdy/models`.
- [ ] Claude Code restore (`docs/session-restore.md`): after a relogin, each
      terminal that was running `claude` reopens on its workspace inside
      that session, a session that ran `/clear` comes back as the cleared
      one, and quitting the resumed Claude leaves a zsh in the same cwd.
- [ ] Under nftables: Tailscale, a podman container's network, and libvirt's
      default network all work.
- [ ] Laptop panel power cycles (`docs/hyprland.md`): the boot greeter's
      stall fell from ~2s to 0.88s with the kernel patch. Still to confirm: a
      logout and login log no `PPS 0 turn panel power off` under
      `drm.debug=0x4`.
- [ ] Desktop: `id -u kevin` must print 1000 before its first rebuild with
      the uid pinned in `system/users.nix`.
- [ ] `tcp_bbr`/`sch_fq` preloaded (`system/physical-host.nix`):
      `systemd-sysctl.service` takes well under 0.1s on every boot.

## Open issues


- [ ] Hyprland (low): the Bitwarden popup rule matches
      `chrome-nngceckbapebfimnlniiiahkandclblb-Default`; check with
      `hyprctl clients` that Helium really gives the popup that class.
- [ ] Spotify does not follow the desktopctl scheme. spicetify-nix bakes
      `color.ini` into the store at build time, so the old `spicetify`
      target (runtime `spicetify update` against a mutable install) cannot
      come back as it was; it is in git history.
