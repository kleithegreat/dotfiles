# Review Audit

Audited on 2026-04-08 against the current repository state.

Status meanings:

- `resolved`: the finding no longer matches the current code.
- `partially addressed`: some follow-up work landed, but the core issue still remains.
- `open`: the finding still matches the current code/docs.

## Tools

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | Not every tool uses the application's own split-file mechanism even when one exists. | open | Ghostty and Vicinae still use concat assembly (`desktopctl/src/theme/targets/ghostty.rs:4-12`, `desktopctl/src/theme/targets/vicinae.rs:8-16`) instead of native include/import surfaces. |
| High | Neovim's generated theme state is wider than the installed theme surface: raw `variant` values do not always map to valid `background` values, and only `gruvbox` is guaranteed to exist locally. | resolved | `config/nvim/lua/plugins/colors.lua:16-46` now accepts only `dark`/`light` `background` values and silently falls back to `gruvbox` unless the generated scheme name is already `gruvbox`. |
| Medium | `vimtex` is lazy-loaded even though upstream recommends loading it eagerly under `lazy.nvim`. | resolved | `config/nvim/lua/plugins/lang.lua:155-187` now sets `lazy = false` for `lervag/vimtex`. |
| Medium | The Neovim 0.12 Treesitter path is much thinner than the 0.11 path and would change behavior materially if activated. | open | The legacy path still configures parser installation, highlight, indent, and textobjects (`config/nvim/lua/plugins/lang.lua:61-84`), while the 0.12 path still only sets `install_dir` (`config/nvim/lua/plugins/lang.lua:87-103`). |
| Medium | Current tmux versions prefer `terminal-features` over `terminal-overrides` for RGB capability declarations. | resolved | `config/tmux/tmux.conf:7-8` now uses `terminal-features` for the Alacritty and Ghostty RGB capability declarations. |
| Medium | `compinit -C` trades startup speed for skipping the new-functions and security checks once the dump exists. | open | `home/shell.nix:29-32` still runs `compinit -C -d "$XDG_CACHE_HOME/zsh/zcompdump"`. |
| Low | Recolor is always enabled in Zathura. | open | `desktopctl/src/theme/targets/zathura.rs:36-39` still emits `set recolor "true"` and `set recolor-keephue "false"` on every apply. |

## Hyprland

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Low | Some rule matches depend on exact titles or classes that may drift. | open | `config/hypr/rules.conf:18-33` still matches exact strings such as `org.freedesktop.impl.portal.desktop.kde`, `chrome-nngceckbapebfimnlniiiahkandclblb-Default`, `Zoom Meeting`, and `\(Incognito\)`. |

## Quickshell

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | `theme.apply` still has no positive completion reporting. | partially addressed | `config/quickshell/shell.qml:24-108` now tokenizes string payloads shell-style instead of using `args.split(" ")`, and `config/quickshell/shell.qml:376-410` reports failures through `ToastService.showError(...)`. The path still has no matching success signal or toast. |
| Medium | `neovide_mono_font_size_offset` exists in theming state but is missing from the editable settings list. | resolved | `config/quickshell/popups/SettingsPopup.qml:55-61` now enumerates Neovide in `monoFontSizeOffsetTargets`, and `config/quickshell/popups/settings/SettingsFontsPane.qml:227-314` renders that full mono-offset list in the editable Fonts pane. |

## NVIDIA

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| High | The laptop hybrid path still depends on hardcoded `/dev/dri/cardN` ordering. | open | `config/hypr/env.conf:13-15` intentionally stays on `AQ_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1` because current Aquamarine splits `AQ_DRM_DEVICES` on `:`, so `/dev/dri/by-path/pci-0000:...` paths crash Hyprland during session startup. |
| Medium | The desktop resume workaround spans several files and one of its key comments still frames it as an experiment. | partially addressed | The lifecycle is now easier to audit because `docs/nvidia/ARCHITECTURE.md` maps the cross-file ownership explicitly, but the live host config still says `powerManagement.kernelSuspendNotifier = false; # Experiment...` (`hosts/desktop/system.nix:61-63`). |
| Low | The PR #996 overlay has only a comment-based removal trigger. | open | `hosts/desktop/system.nix:4-8` and `overlays/nvidia-open-pr996.nix:1-2` still only say to remove the overlay after a future release; there is still no version gate or recorded cutoff in code. |
| Low | The shared unfree allowlist exposes NVIDIA and CUDA closure details without documenting ownership. | open | `system/configuration.nix:123-160` still has no per-entry reason or host annotation for the shared NVIDIA/CUDA-related allowlist entries. |

## Theming

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | Dependency selection is not fully aligned with real consumers. | partially addressed | `font_size` now targets `quickshell` (`desktopctl/src/theme/orchestrator.rs:41-43`, `desktopctl/src/theme/orchestrator.rs:189-190`), but `mono_font` still includes `tmux` (`desktopctl/src/theme/orchestrator.rs:29-38`) even though `tmux` does not consume the mono font family. |
| Low | `neovim` still consumes raw `family` and `variant` strings by design. | open | Centralized app-theme metadata now exists in `desktopctl/src/theme/schema.rs:251-290`, but `desktopctl/src/theme/targets/neovim.rs:19-28` still passes raw values through. |
| Medium | `dark_hint` still has multiple policy initiators and no daemon-owned override model. | open | `desktopctl/src/daemon/night_light.rs:129-163` applies scheduled `dark_hint` writes in `auto`, but `desktopctl/src/theme/mod.rs:252-320` still lets theme surfaces write `dark_hint` directly. |

## Nix

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Low | The `specialArgs` / `extraSpecialArgs` surface is broader than current modules need. | resolved | `flake.nix:55-57` now keeps Home Manager `extraSpecialArgs` to `dotfilesPath`, `hostName`, `vicinae`, `snappy-switcher`, and `opencode`; `home/default.nix:1-16` is the only current consumer surface under `home/`. |
| Low | Host-specific Home Manager branching stays centralized in `home/default.nix`. | open | `home/default.nix:202-235` still selects `hypr/autostart-host.conf`, `hypr/input-devices.conf`, `hypr/monitors.conf`, and `hypr/env.conf` with one centralized `if hostName == ... else if ... else` block. |
| Low | The recursive Quickshell tree plus writable generated sibling file remains a deliberate special case. | partially addressed | The implementation is still the same special case (`home/default.nix:246-249`, `desktopctl/src/theme/targets/quickshell.rs:8-17`, `home/default.nix:329-332`), but the docs now describe the committed `config/quickshell/GeneratedTheme.json` bootstrap snapshot and the runtime overwrite path explicitly. |

## Sun Schedule

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | `dark_hint` still has multiple live policy initiators and no daemon-owned override model. | open | `desktopctl/src/daemon/night_light.rs:129-163` applies scheduled `dark_hint` in `auto`, but `desktopctl/src/theme/mod.rs:252-320` still lets theme surfaces persist `dark_hint` directly. |

## Focus Time

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | Startup recording still depends on at least one successful `hyprctl activewindow -j` seed or a later focus-change event. | open | The daemon seeds at startup and again after each successful socket reconnect (`desktopctl/src/daemon/focus.rs:20-28`, `desktopctl/src/daemon/focus.rs:523-530`), but if those seed attempts return empty and the focused window never changes, unlocked time is still skipped (`desktopctl/src/daemon/focus.rs:47-63`). |
