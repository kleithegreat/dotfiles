# Review Audit

Audited on 2026-04-19 against the current repository state.

This audit now tracks only still-relevant cross-domain findings. Remove resolved
items instead of keeping historical status rows here.

Status meanings:

- `partially addressed`: follow-up work landed, but the core issue remains.
- `open`: the finding still matches the current code or docs.

## Active Findings

| Domain | Severity | Finding | Status | Evidence |
| --- | --- | --- | --- | --- |
| Tools | Medium | The Neovim 0.12 Treesitter path is much thinner than the 0.11 path and would change behavior materially if activated. | open | The legacy Treesitter setup path in `config/nvim/lua/plugins/lang.lua` still configures parser installation, highlight, indent, and textobjects, while the 0.12 path still only sets `install_dir`. |
| Tools | Medium | `compinit -C` trades startup speed for skipping the new-functions and security checks once the dump exists. | open | `home/shell.nix` still runs `compinit -C -d "$XDG_CACHE_HOME/zsh/zcompdump"`. |
| Tools | Low | Recolor is always enabled in Zathura. | open | `desktopctl/src/theme/targets/zathura.rs` still emits `set recolor "true"` and `set recolor-keephue "false"` on every apply. |
| Hyprland | Low | Some rule matches depend on exact titles or classes that may drift. | open | `config/hypr/rules.conf` still matches exact strings such as `org.freedesktop.impl.portal.desktop.kde`, `chrome-nngceckbapebfimnlniiiahkandclblb-Default`, `Zoom Meeting`, and `\(Incognito\)`. |
| NVIDIA | High | The laptop hybrid path still depends on hardcoded `/dev/dri/cardN` ordering. | open | `config/hypr/env.conf` intentionally stays on `AQ_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1` because current Aquamarine splits `AQ_DRM_DEVICES` on `:`, so `/dev/dri/by-path/pci-0000:...` paths crash Hyprland during session startup. |
| NVIDIA | Medium | The desktop no-overlay resume stack is still untested on real hardware. | open | `docs/nvidia/ARCHITECTURE.md`, `docs/nvidia/REVIEW.md`, and `docs/nvidia/QUIRKS.md` all document that the old PR #996 overlay has been removed, but `hosts/desktop/system.nix` still keeps `kernelSuspendNotifier = false`, `NVreg_TemporaryFilePath=/var/tmp`, and the systemd sleep-freeze workaround until a real suspend/resume cycle validates the new stack. |
| NVIDIA | Low | The shared unfree allowlist exposes NVIDIA and CUDA closure details without documenting ownership. | open | `allowedUnfreePackageNames` in `system/configuration.nix` still has no per-entry reason or host annotation for the shared NVIDIA/CUDA-related allowlist entries. |
| Theming | Low | `neovim` still consumes raw `family` and `variant` strings by design. | open | Centralized app-theme metadata now exists in `desktopctl/src/theme/schema.rs`, but `desktopctl/src/theme/targets/neovim.rs` still passes raw values through. |
| Theming / Sun Schedule | Medium | `dark_hint` still has multiple live policy initiators and no daemon-owned override model. | open | `update_solar_status()` / `reconcile_locked()` in `desktopctl/src/daemon/night_light.rs` now issue the scheduled 23:00 enable and 06:00 disable, but `desktopctl/src/theme/mod.rs` still lets theme surfaces write `dark_hint` directly through `set_dark_hint()`, `cmd_set()`, and `cmd_preset()`. |
| Nix | Low | The recursive Quickshell tree plus writable generated sibling file remains a deliberate special case. | partially addressed | The implementation is still the same special case in `home/default.nix` and `desktopctl/src/theme/targets/quickshell.rs`, but the repo no longer carries a missing committed snapshot; docs now describe the `Theme.qml` fallback path plus the runtime-generated `~/.config/quickshell/GeneratedTheme.json` file. |
