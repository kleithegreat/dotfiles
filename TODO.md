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
      brightness drag vs the 30s poll), Wi-Fi join forms including enterprise,
      Display staged apply and its revert countdown, tray menus via
      QsMenuAnchor, and the Bluetooth pane on the laptop — the desktop has no
      bluez running, so the native adapter path is untested on real hardware.

## Open issues

- [ ] Quickshell (low): the Hyprland keybind capture/editor and the animation
      bezier editor were not rebuilt, by decision rather than oversight — both
      remain reachable through `desktopctl hypr keybinds` / `hypr animations`.
      Revisit only if editing them by hand starts to hurt.

- [ ] NVIDIA (high): laptop `AQ_DRM_DEVICES` depends on hardcoded
      `/dev/dri/cardN` ordering, which can shift across boots/updates.
      Blocked on Aquamarine supporting by-path selectors (colons split the
      list); revisit on Aquamarine updates.
- [ ] Theming/sun-schedule (medium): `dark_hint` has two live policy
      initiators (daemon schedule + direct theme writes) and no unified
      override model. Writers commute mechanically now; the remaining work is
      an owner decision on policy.
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
