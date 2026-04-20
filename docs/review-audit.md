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
| Quickshell | Medium | `theme.apply` still has no positive completion reporting. | partially addressed | The `tokenizeThemeArgs` and `themeApplyProc` path in `config/quickshell/shell.qml` now tokenizes string payloads shell-style instead of using `args.split(" ")`, and reports failures through `ToastService.showError(...)`. The path still has no matching success signal or toast. |
| NVIDIA | High | The laptop hybrid path still depends on hardcoded `/dev/dri/cardN` ordering. | open | `config/hypr/env.conf` intentionally stays on `AQ_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1` because current Aquamarine splits `AQ_DRM_DEVICES` on `:`, so `/dev/dri/by-path/pci-0000:...` paths crash Hyprland during session startup. |
| NVIDIA | Medium | The desktop resume workaround spans several files and one of its key comments still frames it as an experiment. | partially addressed | The lifecycle is now easier to audit because `docs/nvidia/ARCHITECTURE.md` maps the cross-file ownership explicitly, but `hosts/desktop/system.nix` still says `powerManagement.kernelSuspendNotifier = false; # Experiment...`. |
| NVIDIA | Low | The PR #996 overlay has only a comment-based removal trigger. | open | `hosts/desktop/system.nix` and `overlays/nvidia-open-pr996.nix` still only say to remove the overlay after a future release; there is still no version gate or recorded cutoff in code. |
| NVIDIA | Low | The shared unfree allowlist exposes NVIDIA and CUDA closure details without documenting ownership. | open | `allowedUnfreePackageNames` in `system/configuration.nix` still has no per-entry reason or host annotation for the shared NVIDIA/CUDA-related allowlist entries. |
| Theming | Low | `neovim` still consumes raw `family` and `variant` strings by design. | open | Centralized app-theme metadata now exists in `desktopctl/src/theme/schema.rs`, but `desktopctl/src/theme/targets/neovim.rs` still passes raw values through. |
| Theming / Sun Schedule | Medium | `dark_hint` still has multiple live policy initiators and no daemon-owned override model. | open | `update_solar_status()` / `reconcile_locked()` in `desktopctl/src/daemon/night_light.rs` issue the nightly `dark_hint` enable, but `desktopctl/src/theme/mod.rs` still lets theme surfaces write `dark_hint` directly through `set_dark_hint()`, `cmd_set()`, and `cmd_preset()`. |
| Nix | Low | The recursive Quickshell tree plus writable generated sibling file remains a deliberate special case. | partially addressed | The implementation is still the same special case in `home/default.nix` and `desktopctl/src/theme/targets/quickshell.rs`, but the docs now describe the committed `config/quickshell/GeneratedTheme.json` bootstrap snapshot and the runtime overwrite path explicitly. |
