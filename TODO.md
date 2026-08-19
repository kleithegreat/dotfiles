# TODO

Open issues and pending validations. Delete entries when resolved.

## Pending validation (needs real hardware / live session)

- [ ] Desktop suspend/resume: validate the post-overlay-removal resume stack
      (see `docs/nvidia.md`). Until a real cycle passes, keep
      `kernelSuspendNotifier = false`, the `/var/tmp` VRAM path, and the
      sleep-freeze workaround.
- [ ] Laptop `e-core-only` profile on the real XPS 15 9520: run
      `laptop-power-profile set e-core-only`, check `cpu*/online`, confirm
      `get` reports the mode and the Quickshell tile doesn't snap back.
- [ ] Laptop VA-API: verify `vainfo` picks up `iHD` via `intel-media-driver`.
- [ ] Quickshell live smoke test after the rewrite: slider drags end to end
      (OSD suppression across a volume drag, night-light commit-on-release,
      brightness drag vs pushed events), Wi-Fi join forms including
      enterprise, Display staged apply and its revert countdown, tray menus
      via QsMenuAnchor, and the Bluetooth pane on the laptop — the desktop has
      no bluez running, so the native adapter path is untested on real
      hardware.
- [ ] Daemon-owned-state migration smoke test (after rebuild; restart the
      daemon before the shell): terminal `desktopctl theme set color_scheme`
      updates an open settings pane; brightness slider tracks Super+F6/F7 and
      OSD appears (event-driven); Super+F8 night-light toggle updates the tile
      promptly; `pkill -x desktopctl` then `theme set` prints the strict
      daemon-unavailable error while `theme status` still prints, and the
      shell reconnects when the daemon returns (verify the QML Socket
      reconnect-by-resetting-`connected` actually retriggers — fall back to a
      Loader-recreated Socket if not); manual `theme set dark_hint true` in
      daytime survives a daemon restart and the schedule reasserts at the next
      edge; hypridle dim/restore restores the original level with no pid file;
      relogin applies the wallpaper through `--wait-daemon` and the laptop
      lid-switch works with the daemon absent. Note the daemon is now a user
      unit: use `systemctl --user stop desktopctl` to test the absent-daemon
      paths, since `pkill` is answered by `Restart=on-failure`.

- [ ] desktopctl user unit (needs a real login): confirm the daemon starts with
      `graphical-session.target` and inherits `WAYLAND_DISPLAY` /
      `HYPRLAND_INSTANCE_SIGNATURE` (the focus tracker and hyprctl calls need
      them), that `systemctl --user stop graphical-session.target` on
      `hyprland.shutdown` takes it down, and that killing an auxiliary
      subsystem no longer takes the socket with it.

- [ ] Theme state seed (needs a rebuild): the live database predates
      `styling/state.json`, so the seed only takes effect on a fresh machine.
      After any state change worth keeping, run
      `desktopctl theme export > styling/state.json` and commit the diff.

## Open issues

- [ ] Quickshell (low): the animation bezier editor was not rebuilt, by
      decision rather than oversight — overrides remain reachable through
      `desktopctl hypr animations`. Revisit only if editing them by hand starts
      to hurt. (The keybind capture/editor and its whole override layer are
      gone: keybinds live in `config/hypr/keybinds.lua` and nothing else.)

- [ ] NVIDIA (high): laptop `AQ_DRM_DEVICES` depends on hardcoded
      `/dev/dri/cardN` ordering, which can shift across boots/updates.
      Blocked on Aquamarine supporting by-path selectors (colons split the
      list); revisit on Aquamarine updates.
- [ ] Nix (medium): drop the EOL Electron insecure exceptions
      (`electron-39.8.10` for bitwarden-desktop, `electron-40.10.5` for
      winboat) once nixpkgs moves those packages to supported Electron.
- [ ] Neovim (medium): the 0.12 Treesitter path only sets `install_dir` and
      is much thinner than the active 0.11 path; activating it would change
      behavior materially.
- [ ] Zsh (low): `compinit -C` skips the new-functions and security checks
      once the dump exists — accepted for startup speed, reconsider if
      completion behaves oddly after adding completions.
- [ ] Nix (low): the NVIDIA/CUDA entries in `allowedUnfreePackageNames` have
      no per-entry reason or host annotation, making cleanup triage harder.

## Owner questions

- [ ] VS Code `config/vscode/base.json` carries settings for uninstalled
      extensions (gitlens, tabnine, copilot, ...) and a `remote.SSH` host
      list (`linux.cse.tamu.edu` + two LAN IPs) — confirm what the laptop
      uses and which hosts are live.
- [ ] Solaar asymmetry: laptop autostart sets `scroll-ratchet Ratcheted` +
      `smart-shift 50`, desktop only `smart-shift 50` — intended?
