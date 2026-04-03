# desktopctl Architecture

## Scope

Current implementation state for the unified `desktopctl` binary and its repo
integration as of 2026-04-03.

## Current Crate Layout

| Piece | Current implementation |
| --- | --- |
| Crate manifest and packaging | `desktopctl/Cargo.toml:1-12` defines the binary crate; `desktopctl/default.nix:1-15`, `overlays/desktopctl.nix:1-3`, and `flake.nix:62-71` package it as a flake-exposed Nix derivation. |
| CLI dispatch | `desktopctl/src/main.rs:13-255` defines the full clap tree for `daemon`, `theme`, `brightness`, `hypr`, `launch-quickshell`, `portal`, and `sun`, and routes each command to the live Rust implementation. |
| Shared path helpers | `desktopctl/src/paths.rs:6-60` resolves the repo root from `DESKTOPCTL_REPO` or `~/repos/dotfiles`, provides shared XDG home/runtime fallbacks, and exposes the shared `desktopctl.db` path. |
| Theme schema and validation | `desktopctl/src/theme/schema.rs:121-404`, `desktopctl/src/theme/schema.rs:406-608`, and `desktopctl/src/theme/resolve.rs:11-500` define the `ColorScheme` and `ThemeState` contract, including explicit scheme `appearance`, centralized app-theme metadata, compiled default theme-state values, canonical field ordering, color-scheme loading, and `theme_state` persistence with legacy `themes/state.json` import support. |
| Theme JSON compatibility | `desktopctl/src/theme/json.rs:4-142` implements Python-style JSON rendering, including preserved object order, 2-space indentation, compact object spacing, and `ensure_ascii=True` escaping used by generated JSON targets and Quickshell-facing CLI output. |
| Theme CLI surface | `desktopctl/src/theme/mod.rs:61-518` implements the migrated `desktopctl theme` command surface, including `all`, `sync`, scoped apply commands, `set`, `preset`, preset-file management, and `status` / `list-*` inspection output. `desktopctl/src/theme/mod.rs:537-1028` adds the filename-ordered JSON list helpers, Python-compatible JSON parse error text, and shared state-update normalization used by the parity audit. |
| Theme orchestration | `desktopctl/src/theme/orchestrator.rs:47-228` and `desktopctl/src/theme/orchestrator.rs:230-383` own generated-file headers, assembly strategies, sync-safe filtering, dependency selection, ordered target application, concat merges, post-write hooks, and best-effort runtime reloads. |
| Theme target registry | `desktopctl/src/theme/targets/mod.rs:24-290` replaces Python auto-discovery with a typed registry and hand-registered target set for all 19 migrated theme targets. |
| Theme targets | File-writing targets live under `desktopctl/src/theme/targets/*.rs`; `desktopctl/src/theme/targets/bat.rs:1-20`, `desktopctl/src/theme/targets/snappy_switcher.rs:1-94`, `desktopctl/src/theme/targets/vicinae.rs:1-51`, and `desktopctl/src/theme/targets/vscode.rs:1-101` now read per-scheme app metadata from `ColorScheme`, while `desktopctl/src/theme/targets/qt.rs:445-628` uses declared `appearance` for light/dark-only asset selection alongside its broader qt5ct/qt6ct/KDE/Kvantum writes. Other notable runtime-heavy ports include `desktopctl/src/theme/targets/cursor.rs:11-221`, `desktopctl/src/theme/targets/gtk.rs:5-71`, `desktopctl/src/theme/targets/quickshell.rs:8-85`, and `desktopctl/src/theme/targets/wallpaper.rs:13-220`. |
| Hyprland helpers | `desktopctl/src/hypr.rs:11-92` wraps `hyprctl activewindow -j`, `hyprctl dispatch`, `hyprctl --batch`, and `.socket2.sock` path discovery for both the Hypr CLI and the daemon. |
| Focus tracker | `desktopctl/src/daemon/focus.rs:20-236`, `desktopctl/src/daemon/focus.rs:238-698`, and `desktopctl/src/daemon/focus.rs:700-902` implement the live focus subsystem: one-second SQLite accumulation, migration from the legacy `focustime.db`, desktop-entry resolution, Hyprland socket listening, and atomic JSON summary writes. |
| Shared solar logic | `desktopctl/src/solar.rs:48-160` and `desktopctl/src/solar.rs:215-259` resolve cached or GeoClue coordinates, compute sunrise/sunset with the NOAA-derived port, and expose `sun status` plus next-event selection. |
| Daemon supervisor | `desktopctl/src/daemon/mod.rs:19-100` starts the focus tracker, solar scheduler, and Unix-socket server under one tokio runtime and coordinates clean shutdown on `SIGTERM` / `SIGINT`. |
| Solar scheduler | `desktopctl/src/daemon/solar.rs:12-99` replaces the old systemd timer script chain with an in-process scheduler that applies the current solar state immediately, sleeps until the next sunrise / sunset / 23:00 event or 2-hour repair tick, drives `hyprsunset`, and updates `dark_hint` through `theme::set_dark_hint()`. |
| Existing helper ports | `desktopctl/src/brightness.rs`, `desktopctl/src/launch.rs`, and `desktopctl/src/portal.rs` remain the active ports for brightness stepping/dimming, Quickshell launch env export, and the directory picker helper. |

## Repo Integration

| Surface | Current implementation |
| --- | --- |
| Nix overlay and package wiring | `system/configuration.nix:5-8` imports the `desktopctl` overlay, `system/configuration.nix:159-162` applies it globally, and `overlays/march-optimized.nix:167-170` optionally rebuilds `desktopctl` with march tuning. |
| Home Manager install and activation | `home/default.nix:33-45` adds `desktopctl` to `home.packages`, and `home/default.nix:310-312` now runs `desktopctl theme sync` during Home Manager activation. |
| Quickshell settings host | `config/quickshell/popups/SettingsPopup.qml:158-223` reads theme state, scheme lists, and presets through `desktopctl theme ... --json`; `config/quickshell/popups/SettingsPopup.qml:553-672` sends all theme mutations through `desktopctl theme set`, `preset`, `save-preset`, and `delete-preset`. |
| Quickshell shell IPC | `config/quickshell/shell.qml:294-306` rewires the shell-level `theme.apply` IPC path to `desktopctl theme ...`. |
| Hyprland autostart | `config/hypr/autostart.conf:4-8` now seeds the brightness cache, launches `desktopctl daemon`, and launches Quickshell through `desktopctl launch-quickshell`. |
| Hyprland keybinds and idle hooks | `config/hypr/keybinds.conf:12-13`, `config/hypr/keybinds.conf:62-63`, and `config/hypr/keybinds.conf:90-91` use `desktopctl hypr toggle-float`, `desktopctl brightness`, and `desktopctl launch-quickshell`; `config/hypr/hypridle.conf:7-12` uses `desktopctl brightness dim` / `restore`. |

## Migration Status

- The Python theming entry point and package are gone: `themes/apply-theme` and
  `themes/lib/` have been removed.
- The legacy session scripts have been removed: `scripts/focus-daemon.py`,
  `scripts/sun-schedule`, `scripts/brightness-step.sh`,
  `scripts/dim-screen.sh`, `scripts/toggle-float.sh`, and
  `scripts/launch-quickshell.sh` are no longer part of the repo.
- The Quickshell directory picker helper and the Home Manager
  `sun-schedule` module are gone: `config/quickshell/scripts/dir-picker.py`
  and `home/sun-schedule.nix` were removed after the migration completed.

## Verification

- A target-by-target audit compared `desktopctl theme target <name>` against the
  removed Python implementation for all 19 migrated theme targets using the same
  theme JSON payload; no byte-level output differences remain.
- `desktopctl/src/theme/targets/mod.rs:293-730` now contains regression tests
  that load the real `themes/colors/*.json` files and assert the centralized
  app-theme metadata used by `bat`, `snappy_switcher`, `vicinae`, and `vscode`.
- `desktopctl/src/theme/targets/qt.rs:968-1017` adds scheme-appearance coverage
  for the `qt` target's KTextEditor and Kvantum dark/light asset selection.
- The CLI parity audit covered `theme set`, `preset`, `save-preset`, and
  `delete-preset`, including exit codes, stdout/stderr text, and resulting
  theme-state JSON / preset JSON content. The only mismatch found was the
  invalid-JSON `save-preset` error string, which is now fixed in Rust.
- The Quickshell-facing JSON modes now match the documented shapes and ordering:
  `theme status --json` mirrors the canonical theme-state JSON shape,
  `theme list-presets --json` matches the preset-file inventory, and
  `theme list-schemes --json` matches the filename-ordered scheme list that QML
  previously built manually.
