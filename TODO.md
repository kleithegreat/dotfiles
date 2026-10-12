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

- [ ] Sliders after the rebuild: `ui/Slider.qml` no longer assigns its own
      `value`, so drag the volume and brightness sliders and then use the
      hotkeys — both must keep following. Seek in Now Playing and watch for
      the bar flicking back before the player reports the new position; if it
      does, the seek needs an optimistic position.
- [ ] Laptop, after the rebuild: remove one enrolled fingerprint in Settings
      → Security and confirm the others survive (`fprintd-delete --finger`
      had never been exercised). Stop the daemon and confirm Screen Time says
      the tracker is not reporting within a few seconds.

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

- [ ] desktopctl (low): `hypr animations save|clear` has no caller in the
      repo — no pane, keybind or script. Either it is the intended manual
      route to animation overrides, or it goes together with the override
      file's seeding in `home/desktopctl.nix` and its Lua reader.
- [ ] Quickshell (medium), structure the cleanup left alone because none of
      it could be tried before a rebuild: `ui/Scroll.qml` and `ui/Choice.qml`
      carry the same glide/overshoot engine twice; the icon button, the
      label/slider/value row and the meter bar are each hand-built in
      several surfaces with drifting sizes; `Appearance`/`Input` and
      `Mullvad`/`Tailscale` are pairwise the same optimistic write queue; the
      "last stderr line to a toast" idiom is pasted into a dozen services.
- [ ] Quickshell (low): `shell.qml` exposes `audio`, `vpn`, `toast` and
      `notifications` IPC targets, and `popups`/`settings` functions, that
      no keybind calls. Kept as the published interface; delete them if
      nothing outside the repo scripts them.
- [ ] Theming (medium): the `command` assembly never carries a command (all
      five targets return an empty batch), the orchestrator has three
      spellings of "apply these targets", colour blending is implemented in
      `schema.rs`, `color_utils.rs`, `opencode.rs`, `spicetify.rs` and
      `starship.rs`, and the quickshell, hyprland and neovim targets emit
      palette keys nothing reads. `wallpaper_dir` is a state key only QML
      reads, and only to derive the colours directory from it by regex.
- [ ] Daemon (medium): `night-light off` publishes its status right after
      `pkill`, before hyprsunset has exited, so the event can still say
      `running`; `NightLight.qml` papers over it with a 2s delayed re-read.
      `sun status` rewrites the location cache to add a place name, which
      refreshes the mtime the 6h freshness check reads, so a stale fix keeps
      looking fresh for as long as the shell polls the weather.
- [ ] Configs (low), unverified against upstream: `ltex.enabled` in
      `config/nvim/lua/config/lsp.lua` lists `"spelling"`, which is not a
      language id; `hyprexpo.gaps_in` in `config/hypr/plugins.lua` may not be
      a key that plugin reads; `config/hypr/rules.lua` still matches
      `google-chrome` incognito and a KDE portal class that nothing
      installed produces.
- [ ] Nix (medium), style rules still broken: derivations defined in a
      `let` instead of an overlay (the patched Discord in `home/packages.nix`,
      `sddmTheme`, `kernelOomNotifier`, `codeLauncher`, `zshShareOnly`,
      `laptopPowerProfile`); short flags in build scripts across `pkgs/`
      (`mkdir -p`, `cp -r`, `install -Dm`, `tar xf`, `sed -i`), which need a
      build of each package to change safely; the Hyprland patch files are
      still named `-0.55` against a 0.56 input.
- [ ] Nix (low): `docs/nix.md` Intent says physical hosts run the stock
      kernel, while `hosts/laptop/system.nix` carries a block of Kconfig
      trims that a Quirk in the same doc describes. One of the two is stale.

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
