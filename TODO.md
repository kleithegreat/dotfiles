# TODO

Open issues and pending validations. Delete entries when resolved.

## Open

- [ ] AirPods never pair from the shell: BlueZ answers "Authentication
      Rejected" (2026-11-13). Likely cause: the adapter is not bondable
      (`Pairable: no`) because nothing registers a pairing agent, and
      Quickshell has none. If a retry with `Pairable` set by hand (busctl;
      lasts until bluetoothd restarts) pairs, set
      `hardware.bluetooth.settings.General.AlwaysPairable = true`, or give
      desktopctl an agent that asks the shell, which changes `docs/airpods.md`
      Intent.

## Later

- [ ] Audit `config/quickshell/` and `config/hypr/` against current upstream
      Quickshell and Hyprland practice; both move fast and this config may
      lag them.

## Pending validation (needs real hardware / live session)

- [ ] Session restore on demand: turn "Restore windows at login" off,
      reboot, and confirm nothing reopens and the power menu offers "Restore
      Windows" once.
- [ ] Session restore after closing things: close a terminal and a Helium
      window, then Shut Down within a few seconds; neither comes back. Same
      for logging out with Super+M, which sends no shutdown announcement.
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

- [ ] Desktop heater: after a switch, toggle Heater mode from the Power pane
      and confirm Quickshell menus stay responsive while both miners run.

- [ ] Claude Code restore (`docs/session-restore.md`): after a relogin, each
      terminal that was running `claude` reopens on its workspace inside
      that session, a session that ran `/clear` comes back as the cleared
      one, and quitting the resumed Claude leaves a zsh in the same cwd.
- [ ] AirPods (`docs/airpods.md`), after a reboot with Bluetooth turned on
      only after login: bluetoothd's journal has no `Failed to Add Adv
      Patterns Monitor`. An unpaired case raises Connect when
      opened, the setup-button step pairs and connects it, and closing the lid
      dismisses the card. A paired case raises its charge, and only at roughly
      arm's length (the RSSI thresholds in `daemon/airpods.rs` are a guess).
      Connected: noise mode and conversation awareness change from the
      Control Center and Settings and follow the stem, the three batteries
      match iOS, and taking a pod out pauses playback while putting it back
      resumes it.
- [ ] AirDrop (`docs/airdrop.md`) with an iPhone: the Control Center tile
      turns Everyone on (Wi-Fi drops on the laptop, since Owly runs exclusive
      there) and off after 10 minutes. The laptop shows in the iPhone's share
      sheet, an offer raises Accept/Decline, and accepted photos land in
      Downloads with "Show in Files" working, and an offer shows the photo's
      thumbnail (if not, desktopctl's journal logs the format's first
      bytes). Wi-Fi comes back after. Sharing: AirDrop in Nautilus's and
      Helium's right-click menus and Super+Shift+A each raise the share sheet
      after a relogin; note how the iPhone takes a sentence (a .txt), and a lone link
      as a link.
- [ ] Under nftables: Tailscale, a podman container's network, and libvirt's
      default network all work.
- [ ] Laptop panel power cycles (`docs/hyprland.md`): the boot greeter's
      stall fell from ~2s to 0.88s with the kernel patch. Still to confirm: a
      logout and login log no `PPS 0 turn panel power off` under
      `drm.debug=0x4`.
- [ ] Desktop: `id -u kevin` must print 1000 before its first rebuild with
      the uid pinned in `system/users.nix`.
- [ ] Desktop: with `tcp_bbr`/`sch_fq` preloaded (`system/physical-host.nix`),
      `systemd-sysctl.service` takes well under 0.1s (the laptop passes).
- [ ] Laptop boot after the uvm softdep patch and initrd trim
      (`docs/nvidia.md`): `systemd-modules-load` no longer waits on NVIDIA,
      `lsmod` shows `nvidia_uvm`, a CUDA app runs, and login reaches Hyprland
      (`AQ_DRM_DEVICES` needs `/dev/dri/nvidia-gpu` by then).

## Open issues


- [ ] Hyprland (low): the Bitwarden popup rule matches
      `chrome-nngceckbapebfimnlniiiahkandclblb-Default`; check with
      `hyprctl clients` that Helium really gives the popup that class.
- [ ] Spotify does not follow the desktopctl scheme. spicetify-nix bakes
      `color.ini` into the store at build time, so the old `spicetify`
      target (runtime `spicetify update` against a mutable install) cannot
      come back as it was; it is in git history.
