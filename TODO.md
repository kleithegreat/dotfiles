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
- [ ] Displays subsystem, multi-monitor half (needs an external display
      attached): plug and unplug one and confirm the wallpaper lands on it,
      the bar and every surface move to it, and workspaces 1-10 follow — then
      that unplugging hands all three back to the built-in panel. Toggle
      "Main display" onto the internal panel with an external attached and
      confirm that choice survives a relogin, and that a *different* unknown
      monitor still auto-selects. Drag a display in the arrangement canvas and
      check the edge snap and the countdown's revert with two outputs.
      Single-output behaviour is confirmed on the laptop: staged apply, Keep,
      scale persisting across reloads, and the auto fallback to `eDP-1` when
      the external went away.

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

- [ ] macOS VM, end to end (needs a guest install): nothing in it has been
      booted. `macos-vm fetch` → `install` → `run`, then check that the
      reims-vgpu device's own Vulkan window opens on the desktop, that
      `nvidia-offload macos-vm run` on the laptop reaches the 3050 rather than
      Intel's ANV, and that `--console` still shows OpenCore. The package has
      only been built on the desktop; the laptop has not compiled it yet.
      See `docs/macos-vm.md`.

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

- [ ] Quickshell (medium): the Pointer pane's "Scrolling" slider writes
      `input:scroll_factor`, which the touchpad ignores — the laptop's
      `input:touchpad:scroll_factor` (0.25, in `hosts/laptop/input-devices.lua`)
      is not reachable from any UI. Scroll speed inside the shell is now
      consistent between panes and option strips, but if it still feels slow,
      that hardcoded 0.25 is the knob and it wants a home in
      `input-defaults.lua` with the rest.

- [ ] GeoClue (medium): it resolves no real location on either host — the IP
      source is disabled (`Unknown IP source method '(null)'`) and the WiFi
      source lost its backend when Mozilla Location Service shut down in 2024,
      so `where-am-i` returns a fallback rather than an answer. On the desktop
      this set the timezone to Denver and left sun-schedule's cache stuck at
      `39.6002,-104.89` (Greenwood Village CO), which is why that host now pins
      both `time.timeZone` and `DESKTOPCTL_LOCATION`; the laptop still trusts
      GeoClue via `automatic-timezoned`. The desktop's pin outranks the cache,
      so nothing needs deleting there, but delete
      `$XDG_CACHE_HOME/sun-schedule/location.json` on the laptop once the source
      works, since a stale cache is preferred over a live lookup for 6h and is
      the fourth fallback after that. Either give GeoClue a working IP source or
      drop it for static coordinates on the laptop too; if it goes,
      the laptop needs a different timezone story and `location.provider`,
      `services.geoclue2`, and the `where-am-i` path in `docs/sun-schedule.md`
      go with it.

## Owner questions

- [ ] VS Code `config/vscode/base.json` carries settings for uninstalled
      extensions (gitlens, tabnine, copilot, ...) and a `remote.SSH` host
      list (`linux.cse.tamu.edu` + two LAN IPs) — confirm what the laptop
      uses and which hosts are live.
- [ ] Solaar asymmetry: laptop autostart sets `scroll-ratchet Ratcheted` +
      `smart-shift 50`, desktop only `smart-shift 50` — intended?
