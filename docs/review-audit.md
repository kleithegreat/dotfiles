# Review Audit

Audited on 2026-04-08 against the current repository state.

Status meanings:

- `resolved`: the finding no longer matches the current code.
- `partially addressed`: some follow-up work landed, but the core issue still remains.
- `open`: the finding still matches the current code/docs.

## Tools

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | Not every tool uses the application's own split-file mechanism even when one exists. | resolved | `config/ghostty/config` now delegates to `~/.config/ghostty/theme.conf` through Ghostty's native `config-file` directive, and `config/vicinae/settings.json` now imports `settings.theme.json` while `desktopctl/src/theme/targets/ghostty.rs` and `desktopctl/src/theme/targets/vicinae.rs` write only the generated fragments. |
| High | Neovim's generated theme state is wider than the installed theme surface: raw `variant` values do not always map to valid `background` values, and only `gruvbox` is guaranteed to exist locally. | resolved | `config/nvim/lua/plugins/colors.lua` now accepts only `dark`/`light` `background` values and silently falls back to `gruvbox` unless the generated scheme name is already `gruvbox`. |
| Medium | `vimtex` is lazy-loaded even though upstream recommends loading it eagerly under `lazy.nvim`. | resolved | `config/nvim/lua/plugins/lang.lua` now sets `lazy = false` for `lervag/vimtex`. |
| Medium | The Neovim 0.12 Treesitter path is much thinner than the 0.11 path and would change behavior materially if activated. | open | The legacy Treesitter setup path in `config/nvim/lua/plugins/lang.lua` still configures parser installation, highlight, indent, and textobjects, while the 0.12 path still only sets `install_dir`. |
| Medium | Current tmux versions prefer `terminal-features` over `terminal-overrides` for RGB capability declarations. | resolved | `config/tmux/tmux.conf` now uses `terminal-features` for the Alacritty and Ghostty RGB capability declarations. |
| Medium | `compinit -C` trades startup speed for skipping the new-functions and security checks once the dump exists. | open | `home/shell.nix` still runs `compinit -C -d "$XDG_CACHE_HOME/zsh/zcompdump"`. |
| Low | Recolor is always enabled in Zathura. | open | `desktopctl/src/theme/targets/zathura.rs` still emits `set recolor "true"` and `set recolor-keephue "false"` on every apply. |

## Hyprland

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Low | Some rule matches depend on exact titles or classes that may drift. | open | `config/hypr/rules.conf` still matches exact strings such as `org.freedesktop.impl.portal.desktop.kde`, `chrome-nngceckbapebfimnlniiiahkandclblb-Default`, `Zoom Meeting`, and `\(Incognito\)`. |

## Quickshell

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | `theme.apply` still has no positive completion reporting. | partially addressed | The `tokenizeThemeArgs` and `themeApplyProc` path in `config/quickshell/shell.qml` now tokenizes string payloads shell-style instead of using `args.split(" ")`, and reports failures through `ToastService.showError(...)`. The path still has no matching success signal or toast. |
| Medium | `neovide_mono_font_size_offset` exists in theming state but is missing from the editable settings list. | resolved | `config/quickshell/popups/SettingsPopup.qml` now enumerates Neovide in `monoFontSizeOffsetTargets`, and `config/quickshell/popups/settings/SettingsFontsPane.qml` renders that full mono-offset list in the editable Fonts pane. |

## NVIDIA

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| High | The laptop hybrid path still depends on hardcoded `/dev/dri/cardN` ordering. | open | `config/hypr/env.conf` intentionally stays on `AQ_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1` because current Aquamarine splits `AQ_DRM_DEVICES` on `:`, so `/dev/dri/by-path/pci-0000:...` paths crash Hyprland during session startup. |
| Medium | The desktop resume workaround spans several files and one of its key comments still frames it as an experiment. | partially addressed | The lifecycle is now easier to audit because `docs/nvidia/ARCHITECTURE.md` maps the cross-file ownership explicitly, but `hosts/desktop/system.nix` still says `powerManagement.kernelSuspendNotifier = false; # Experiment...`. |
| Low | The PR #996 overlay has only a comment-based removal trigger. | open | `hosts/desktop/system.nix` and `overlays/nvidia-open-pr996.nix` still only say to remove the overlay after a future release; there is still no version gate or recorded cutoff in code. |
| Low | The shared unfree allowlist exposes NVIDIA and CUDA closure details without documenting ownership. | open | `allowedUnfreePackageNames` in `system/configuration.nix` still has no per-entry reason or host annotation for the shared NVIDIA/CUDA-related allowlist entries. |

## Theming

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | Dependency selection is not fully aligned with real consumers. | resolved | `desktopctl/src/theme/mod.rs` no longer routes `theme fonts` through `tmux`, and `desktopctl/src/theme/orchestrator.rs` no longer includes `tmux` in the `mono_font` dependency path. |
| Low | `neovim` still consumes raw `family` and `variant` strings by design. | open | Centralized app-theme metadata now exists in `desktopctl/src/theme/schema.rs`, but `desktopctl/src/theme/targets/neovim.rs` still passes raw values through. |
| Medium | `dark_hint` still has multiple policy initiators and no daemon-owned override model. | open | `update_solar_status()` / `reconcile_locked()` in `desktopctl/src/daemon/night_light.rs` issue the nightly `dark_hint` enable, but `desktopctl/src/theme/mod.rs` still lets theme surfaces write `dark_hint` directly through `set_dark_hint()`, `cmd_set()`, and `cmd_preset()`. |

## Nix

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Low | The `specialArgs` / `extraSpecialArgs` surface is broader than current modules need. | resolved | `flake.nix` now keeps Home Manager `extraSpecialArgs` to `dotfilesPath`, `hostName`, `vicinae`, `snappy-switcher`, and `opencode`; `home/default.nix` is the only current consumer surface under `home/`. |
| Low | Host-specific Home Manager branching stays centralized in `home/default.nix`. | resolved | `home/default.nix` now resolves the Hyprland host-specific files through the local `hyprHostConfigs` attrset plus `mkHostConfigFile`, instead of repeating an `if hostName == ... else if ... else` chain for each path. |
| Low | The recursive Quickshell tree plus writable generated sibling file remains a deliberate special case. | partially addressed | The implementation is still the same special case in `home/default.nix` and `desktopctl/src/theme/targets/quickshell.rs`, but the docs now describe the committed `config/quickshell/GeneratedTheme.json` bootstrap snapshot and the runtime overwrite path explicitly. |

## Sun Schedule

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | `dark_hint` still has multiple live policy initiators and no daemon-owned override model. | open | `update_solar_status()` / `reconcile_locked()` in `desktopctl/src/daemon/night_light.rs` issue the nightly `dark_hint` enable, but `desktopctl/src/theme/mod.rs` still lets theme surfaces persist `dark_hint` directly through `set_dark_hint()`, `cmd_set()`, and `cmd_preset()`. |

## Focus Time

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | Startup recording still depends on at least one successful `hyprctl activewindow -j` seed or a later focus-change event. | resolved | `desktopctl/src/daemon/focus.rs` now retries `hyprctl activewindow -j` on unlocked ticks when the shared class is empty, so startup or reconnect seeds no longer need a later focus-change event to begin unlocked accumulation. |
