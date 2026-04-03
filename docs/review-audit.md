# Review Audit

Audited on 2026-04-03 against the current repository state.

Status meanings:

- `addressed`: the review finding no longer matches the current code/docs.
- `partially addressed`: some follow-up work landed, but the core issue still remains.
- `open`: the finding still matches the current code/docs.

## Tools

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | The repo still contains committed generated snapshots for Ghostty, Starship, and Vicinae. | open | `config/ghostty/config`, `config/starship/starship.toml`, `config/vicinae/settings.json`, and `config/vicinae/vicinae.json` still exist. Live targets still read `config/ghostty/base`, `config/starship/base.toml`, and `config/vicinae/base.json` and write elsewhere (`desktopctl/src/theme/targets/ghostty.rs:4-8`, `desktopctl/src/theme/targets/starship.rs:4-8`, `desktopctl/src/theme/targets/vicinae.rs:8-12`). |
| Medium | Not every tool uses the application's own split-file mechanism even when one exists. | open | Ghostty and Vicinae still use `Assembly::Concat` (`desktopctl/src/theme/targets/ghostty.rs:4-29`, `desktopctl/src/theme/targets/vicinae.rs:8-68`). Their repo bases are still plain base files, not include/import stubs (`config/ghostty/base:1-2`, `config/vicinae/base.json:1-15`). |
| High | Neovim's generated theme state is wider than the installed theme surface: raw `variant` values do not always map to valid `background` values, and only `gruvbox` is guaranteed to exist locally. | open | `desktopctl/src/theme/targets/neovim.rs:19-28` still writes raw `family` and `variant` into `colorscheme` and `background`. `config/nvim/lua/plugins/colors.lua:27-36` still only configures/loads `gruvbox` and falls back to `gruvbox` if the requested colorscheme is missing. The theme catalog still includes non-binary variants such as `catppuccin/mocha`, `rosepine/dawn`, and `tokyonight/night` (`themes/colors/catppuccin-mocha.json:2-3`, `themes/colors/rose-pine-dawn.json:2-3`, `themes/colors/tokyo-night.json:2-3`). |
| Medium | `vimtex` is lazy-loaded even though upstream recommends loading it eagerly under `lazy.nvim`. | open | `config/nvim/lua/plugins/lang.lua:155-187` still gates `lervag/vimtex` behind `ft = { "tex", "plaintex", "bib" }`. |
| Medium | The Neovim 0.12 Treesitter path is much thinner than the 0.11 path and would change behavior materially if activated. | open | The legacy path still configures parser installation, highlight, indent, and textobjects (`config/nvim/lua/plugins/lang.lua:61-85`), while the 0.12 path still only sets `install_dir` (`config/nvim/lua/plugins/lang.lua:87-103`). |
| Medium | The current Ghostty design is close to full-file generation even though Ghostty supports split config through `config-file`. | open | Ghostty still uses concat assembly (`desktopctl/src/theme/targets/ghostty.rs:4-29`), and the repo base still contains only comments instead of a native include structure (`config/ghostty/base:1-2`). |
| Medium | Current tmux versions prefer `terminal-features` over `terminal-overrides` for RGB capability declarations. | open | `config/tmux/tmux.conf:7-8` still sets `terminal-overrides` and has no `terminal-features` entry. |
| Medium | `compinit -C` trades startup speed for skipping the new-functions and security checks once the dump exists. | open | `home/shell.nix:15-19` still runs `compinit -C -d "$XDG_CACHE_HOME/zsh/zcompdump"`. |
| Medium | Vicinae supports imported fragments, but the repo still uses merge-based generation, and the theme map still misses some live family spellings. | open | Vicinae still uses concat assembly (`desktopctl/src/theme/targets/vicinae.rs:8-12`). Its mapping still expects spellings like `rose-pine` and `tokyo-night` (`desktopctl/src/theme/targets/vicinae.rs:19-35`), while live schemes use `rosepine`, `tokyonight`, and `nord/light` (`themes/colors/rose-pine.json:2-3`, `themes/colors/rose-pine-dawn.json:2-3`, `themes/colors/tokyo-night.json:2-3`, `themes/colors/tokyo-night-light.json:2-3`, `themes/colors/nord-light.json:2-3`). |
| Low | Recolor is always enabled in Zathura. | open | `desktopctl/src/theme/targets/zathura.rs:36-39` still emits `set recolor "true"` and `set recolor-keephue "false"` on every apply. |

## Hyprland

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | `autostart.conf` applies a hardcoded wallpaper via `awww img` at session start. | addressed | `config/hypr/autostart.conf:12-13` now keeps the `awww-daemon` bootstrap but reapplies wallpaper through `desktopctl theme wallpaper`, so the initial wallpaper comes from persisted theme state. |
| Low | Some rule matches depend on exact titles or classes that may drift. | open | `config/hypr/rules.conf:18-32` still matches exact strings such as `org.freedesktop.impl.portal.desktop.kde`, `chrome-nngceckbapebfimnlniiiahkandclblb-Default`, `Zoom Meeting`, and `\(Incognito\)`. |
| Low | The bind set does not use newer descriptive or repeat-oriented forms such as `bindd` or `binde`. | addressed | `config/hypr/keybinds.conf:9-98` now uses `bindd` throughout and `bindde` for repeat-on-hold keys such as brightness and volume. `bindm` remains only for mouse move/resize dispatchers. |

## Quickshell

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| High | Quick Settings chevrons still emit expand signals that nothing consumes. | addressed | `config/quickshell/popups/QuickSettingsPopup.qml:26-30` still declares the expand signals, but `config/quickshell/PopupOverlayHost.qml:13-17` and `config/quickshell/PopupOverlayHost.qml:167-172` now consume them by closing Quick Settings, opening Settings, and selecting the target pane. |
| Medium | `theme.apply` IPC still splits argv unsafely and does not report completion or failure. | partially addressed | `config/quickshell/shell.qml:24-108` now tokenizes string payloads shell-style instead of using `args.split(" ")`, and `config/quickshell/shell.qml:380-415` now reports failures through `ToastService.showError(...)`. The path still has no positive success notification. |
| Medium | Quickshell font-size controls do not update Quickshell chrome. | addressed | `desktopctl/src/theme/targets/quickshell.rs:20-22`, `desktopctl/src/theme/targets/quickshell.rs:79-81` now derive shell font sizes from `ThemeState.font_size`, and `desktopctl/src/theme/orchestrator.rs:41-43`, `desktopctl/src/theme/orchestrator.rs:189-190` now route `font_size` changes back to the `quickshell` target. |
| Medium | `system_font` has no visible effect on shell chrome. | addressed | The quickshell target still emits both `family` and `systemFamily` (`desktopctl/src/theme/targets/quickshell.rs:73-81`), and shell chrome now consumes `Theme.systemFamily` across notification, popup, bar-label, and settings text surfaces such as `config/quickshell/shell.qml:200-205`, `config/quickshell/popups/QuickSettingsPopup.qml:341-348`, `config/quickshell/NotifDrawer.qml:142-225`, and `config/quickshell/bar/Brightness.qml:49`. Clock and glyph-oriented surfaces remain on `Theme.fontFamily` by design. |
| Medium | `neovide_mono_font_size_offset` exists in theming state but is missing from the editable settings list. | open | Theme state still contains `neovide_mono_font_size_offset` (`desktopctl/src/theme/schema.rs:284-289`, `desktopctl/src/theme/orchestrator.rs:191-196`), but `config/quickshell/popups/SettingsPopup.qml:52-58` still only enumerates Alacritty, Ghostty, GTK, Qt, and VS Code offsets. |

## NVIDIA

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| High | The laptop hybrid path still depends on hardcoded `/dev/dri/cardN` ordering. | open | `config/hypr/env.conf:13-16` still sets `AQ_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1`. |
| Medium | The shared baseline still carries laptop-specific Mesa-only EGL policy. | addressed | `system/configuration.nix:217-223` no longer sets `__EGL_VENDOR_LIBRARY_FILENAMES`. `hosts/laptop/system.nix:63-64` now owns the laptop's Mesa-only value, and `hosts/desktop/system.nix:69-71` sets the desktop's dual-vendor EGL list directly without `lib.mkForce`. |
| Medium | The desktop resume workaround spans several files and one of its key comments still frames it as an experiment. | partially addressed | The lifecycle is now easier to audit because `docs/nvidia/ARCHITECTURE.md:21-35` maps the cross-file ownership explicitly, but the live host config still says `powerManagement.kernelSuspendNotifier = false; # Experiment...` (`hosts/desktop/system.nix:57-61`). |
| Low | The PR #996 overlay has only a comment-based removal trigger. | open | `hosts/desktop/system.nix:4-8` and `overlays/nvidia-open-pr996.nix:1-2` still only say to remove the overlay after a future release; there is still no version gate or recorded cutoff in code. |
| Low | The shared unfree allowlist exposes NVIDIA and CUDA closure details without documenting ownership. | partially addressed | `docs/nvidia/ARCHITECTURE.md:23-27` now at least identifies the allowlist as shared ownership in `system/configuration.nix`, but the live list itself still has no per-entry reason or host annotation (`system/configuration.nix:85-122`). |

## Theming

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| High | Variant and family normalization is not centralized. | open | Theme files still use families and variants such as `rosepine/dawn` and `tokyonight/night` (`themes/colors/rose-pine-dawn.json:2-3`, `themes/colors/tokyo-night.json:2-3`). Normalization still lives piecemeal in per-target logic: raw pass-through in `neovim` (`desktopctl/src/theme/targets/neovim.rs:19-28`), hand-written mapping in `vicinae` (`desktopctl/src/theme/targets/vicinae.rs:19-35`) and `vscode` (`desktopctl/src/theme/targets/vscode.rs:22-44`), and dark/light branching in `qt` (`desktopctl/src/theme/targets/qt.rs:445-450`). |
| Medium | Dependency selection is not fully aligned with real consumers. | partially addressed | `font_size` now targets `quickshell` (`desktopctl/src/theme/orchestrator.rs:41-43`, `desktopctl/src/theme/orchestrator.rs:189-190`), but `mono_font` still includes `tmux` (`desktopctl/src/theme/orchestrator.rs:29-38`) even though `tmux` does not consume the mono font family. |
| Medium | The repo still carries stale generated snapshots. | open | `config/ghostty/config`, `config/starship/starship.toml`, `config/vicinae/settings.json`, and `config/vicinae/vicinae.json` still exist, while the live targets still read/write elsewhere (`desktopctl/src/theme/targets/ghostty.rs:4-8`, `desktopctl/src/theme/targets/starship.rs:4-8`, `desktopctl/src/theme/targets/vicinae.rs:8-12`). |
| Medium | `dark_hint` has multiple policy initiators and no override model. | addressed | `desktopctl/src/theme/mod.rs:254-324` now routes direct `dark_hint` writes and preset-provided `dark_hint` values through `crate::night_light::request_mode(...)`, so Quickshell settings (`config/quickshell/popups/SettingsPopup.qml:891-896`), presets (`config/quickshell/popups/settings/SettingsPresetEditor.qml:397-484`), and shell IPC all delegate to the daemon-owned night-light controller instead of mutating live state independently. |
| Medium | `hyprsunset` has three direct writers with no arbiter. | addressed | The daemon-owned controller is now the only live writer of `hyprsunset` (`desktopctl/src/daemon/night_light.rs:123-161`). Quickshell `DisplayService` requests daemon-backed mode changes through `desktopctl night-light ...`, and Hyprland keybinds request `desktopctl night-light toggle` / `auto` (`config/hypr/keybinds.conf:74-75`) instead of spawning `hyprsunset` directly. |
| Medium | Quickshell `system_font` binding drift. | addressed | The quickshell target still exposes both font families (`desktopctl/src/theme/targets/quickshell.rs:73-81`), and the shell now binds `Theme.systemFamily` across bar labels, popup text, notification text, and settings chrome instead of concentrating it in the settings editor. |
| Low | `config/hypr/autostart.conf` contains a hardcoded `awww img` path that sets the initial wallpaper independently of theme state. | addressed | `config/hypr/autostart.conf:12-13` now bootstraps wallpaper through `desktopctl theme wallpaper` rather than a fixed repo path. |

## Nix

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| Medium | `mkHost` expresses the target platform indirectly through an inline `nixpkgs.hostPlatform` module instead of an explicit `system = "x86_64-linux"` call site. | addressed | `flake.nix:39-45` now passes `system = "x86_64-linux"` directly to `nixosSystem`, and evaluation still resolves `pkgs.stdenv.hostPlatform.system` to `x86_64-linux` for `desktop`, `laptop`, and `vm`. |
| Low | The `specialArgs` / `extraSpecialArgs` surface is broader than current modules need. | open | `flake.nix:40-57` still passes both `inputs` and individual flake inputs. Current consumers mainly use `inputs` in `system/configuration.nix:1-11` and `system/configuration.nix:19-20`, plus `dotfilesPath`/`hostName`/`vicinae`/`snappy-switcher` in `home/default.nix:1-10`, `home/default.nix:184-242`, and `home/default.nix:307`; several individually-passed args remain unused in Home Manager. |
| Low | Host-specific Home Manager branching stays centralized in `home/default.nix`. | open | `home/default.nix:188-215` still selects `hypr/input-devices.conf`, `hypr/monitors.conf`, and `hypr/env.conf` with one centralized `if hostName == ... else if ... else` block. |
| Low | The recursive Quickshell tree plus writable generated sibling file remains a deliberate special case. | partially addressed | The implementation is still the same special case (`home/default.nix:226-233`, `desktopctl/src/theme/targets/quickshell.rs:8-16`, `home/default.nix:310-312`), but `docs/nix/ARCHITECTURE.md:61-80` now documents the arrangement explicitly. |
| Low | `config/ghostty/config`, `config/starship/starship.toml`, `config/vicinae/settings.json`, and `config/vicinae/vicinae.json` are inert generated snapshots still committed under `config/`. | open | Those files still exist, and the live theme bases/outputs are still elsewhere (`desktopctl/src/theme/targets/ghostty.rs:4-8`, `desktopctl/src/theme/targets/starship.rs:4-8`, `desktopctl/src/theme/targets/vicinae.rs:8-12`). |

## Sun Schedule

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| High | `hyprsunset` has three direct writers. | addressed | The daemon-owned night-light controller now arbitrates all live `hyprsunset` changes, while Quickshell and Hyprland only request mode changes through `desktopctl night-light ...` instead of spawning or killing the process directly. |
| High | `dark_hint` has multiple policy initiators and no override model. | addressed | Direct `dark_hint` requests from theme surfaces are now delegated back through the daemon-owned night-light controller (`desktopctl/src/theme/mod.rs:254-324`), so the runtime ownership conflict called out in the earlier review is no longer present. |

## Focus Time

| Severity | Finding | Status | Evidence |
| --- | --- | --- | --- |
| High | The JSON contract has no freshness or liveness field, so Quickshell cannot tell a live daemon from a stale last write. | open | The summary writer still serializes only `selected_date`, `total`, `average`, `week_range`, `yesterday`, `current`, `apps`, `week`, and `month` (`desktopctl/src/daemon/focus.rs:134-145`, `desktopctl/src/daemon/focus.rs:566-633`). `config/quickshell/popups/settings/SettingsFocusTimePane.qml:44-64` still only distinguishes parseable/non-empty JSON from no data. |
| Medium | Aggregate totals include `Desktop` and `Quickshell`, but the visible app list and current-app label hide those classes. | open | Aggregate queries still exclude only `__locked__` (`desktopctl/src/daemon/focus.rs:223-240`, `desktopctl/src/daemon/focus.rs:294-304`), while apps/current still hide `Desktop` and `Quickshell` via `excluded_classes()` (`desktopctl/src/daemon/focus.rs:199-205`, `desktopctl/src/daemon/focus.rs:252-289`, `desktopctl/src/daemon/focus.rs:417-418`). |
| Medium | Socket outages preserve the last seen focused class until reconnect, with no re-sync query after the disconnect. | open | `desktopctl/src/daemon/focus.rs:365-396` still reconnects to the same socket path, sleeps, and retries, but never clears `current_class` or re-runs `hyprctl activewindow -j` after a disconnect. |
| Medium | Startup recording depends on one successful `hyprctl activewindow -j` call or a later focus-change event. | open | The daemon still seeds with `get_active_class()` once at startup (`desktopctl/src/daemon/focus.rs:20-25`, `desktopctl/src/daemon/focus.rs:353-362`). If that is empty and no later `activewindow>>` event arrives, the main loop still skips unlocked accumulation (`desktopctl/src/daemon/focus.rs:50-56`). |
| Low | The SQLite store has no retention, pruning, or compaction path. | open | `desktopctl/src/daemon/focus.rs:70-101` still only creates the three tables and enables WAL; there is still no prune/vacuum/retention path. |
| Low | The empty-state message in QML conflates missing file, unreadable file, and invalid JSON with "daemon is not running". | open | `config/quickshell/popups/settings/SettingsFocusTimePane.qml:50-61` still maps both empty output and parse failure to `hasData = false`, and `config/quickshell/popups/settings/SettingsFocusTimePane.qml:126-138` still renders the single message "The focus time daemon is not running". |
