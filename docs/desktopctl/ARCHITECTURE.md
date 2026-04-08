# desktopctl Architecture

## Scope

Current implementation state for the unified `desktopctl` binary and its repo
integration as of 2026-04-08.

## Current Crate Layout

| Piece | Current implementation |
| --- | --- |
| Crate manifest and packaging | `desktopctl/Cargo.toml:1-12` defines the binary crate; `desktopctl/default.nix:1-15`, `overlays/desktopctl.nix:1-3`, and `flake.nix:62-71` package it as a flake-exposed Nix derivation. |
| CLI dispatch | `desktopctl/src/main.rs:14-285` defines the full clap tree for `daemon`, `theme`, `brightness`, `hypr`, `launch-quickshell`, `portal`, `night-light`, and `sun`, and routes each command to the live Rust implementation. |
| Shared path helpers | `desktopctl/src/paths.rs:6-66` resolves the repo root from `DESKTOPCTL_REPO` or `~/repos/dotfiles`, exposes `repo_path()` for repo-relative helper lookups, provides shared XDG home/runtime fallbacks, and exposes the shared `desktopctl.db` path. |
| Theme schema and validation | `desktopctl/src/theme/schema.rs:121-580` and `desktopctl/src/theme/resolve.rs:11-500` define the `ColorScheme` and `ThemeState` contract, including required scheme `appearance`, centralized app-theme metadata, compiled default theme-state values, canonical field ordering, color-scheme loading, and `theme_state` persistence with legacy `themes/state.json` import support. |
| Theme JSON compatibility | `desktopctl/src/theme/json.rs:4-142` implements Python-style JSON rendering, including preserved object order, 2-space indentation, compact object spacing, and `ensure_ascii=True` escaping used by generated JSON targets and Quickshell-facing CLI output. |
| Theme CLI surface | `desktopctl/src/theme/mod.rs:65-569` implements the current `desktopctl theme` command surface, including `all`, `sync`, scoped apply commands, `set`, `preset`, preset-file management, and `status` / `list-*` inspection output. `desktopctl/src/theme/mod.rs:73-95` still persists and applies `dark_hint` directly through the theming module, and `desktopctl/src/theme/mod.rs:318-388` lets `theme set dark_hint ...` and preset-supplied `dark_hint` values take that same direct path without routing through the daemon. |
| Theme orchestration | `desktopctl/src/theme/orchestrator.rs:16-52`, `desktopctl/src/theme/orchestrator.rs:55-236`, `desktopctl/src/theme/orchestrator.rs:238-325`, and `desktopctl/src/theme/orchestrator.rs:517-520` own generated-file headers, assembly strategies, sync-safe filtering, dependency selection, ordered target application, atomic file replacement, concat merges, repo-relative base-path resolution, post-write hooks, and best-effort runtime reloads. The current dependency map includes both `quickshell` and `gtksourceview` in the color-fanout tables (`desktopctl/src/theme/orchestrator.rs:16-52`, `desktopctl/src/theme/orchestrator.rs:176-215`). |
| Theme target registry | `desktopctl/src/theme/targets/mod.rs:25-297` replaces Python auto-discovery with a typed registry and hand-registered target set for all 20 current theme targets. |
| Theme targets | File-writing targets live under `desktopctl/src/theme/targets/*.rs`; `desktopctl/src/theme/targets/bat.rs:1-20`, `desktopctl/src/theme/targets/snappy_switcher.rs:11-94`, `desktopctl/src/theme/targets/vicinae.rs:8-51`, and `desktopctl/src/theme/targets/vscode.rs:9-100` read per-scheme app metadata from `ColorScheme`, the concat targets now declare repo-relative `base_path` values instead of `~/repos/dotfiles/...`, and `desktopctl/src/theme/targets/qt.rs:445-628` uses declared `appearance` for light/dark-only asset selection alongside its broader qt5ct/qt6ct/KDE/Kvantum writes. Other notable runtime-heavy ports include `desktopctl/src/theme/targets/cursor.rs:11-221`, `desktopctl/src/theme/targets/gtk.rs:5-72`, `desktopctl/src/theme/targets/gtksourceview.rs:13-311`, `desktopctl/src/theme/targets/quickshell.rs:19-89`, and `desktopctl/src/theme/targets/wallpaper.rs:13-220`. |
| Hyprland helpers | `desktopctl/src/hypr.rs:22-176` wraps `hyprctl activewindow -j`, `hyprctl dispatch`, `hyprctl --batch`, and `.socket2.sock` path discovery for both the Hypr CLI and the daemon. Socket lookup now prefers the current `HYPRLAND_INSTANCE_SIGNATURE`, falls back to `/tmp/hypr/<sig>/.socket2.sock`, and otherwise picks the newest discovered socket under the runtime or `/tmp/hypr` trees. |
| Focus tracker | `desktopctl/src/daemon/focus.rs:20-236`, `desktopctl/src/daemon/focus.rs:238-698`, and `desktopctl/src/daemon/focus.rs:700-902` implement the live focus subsystem: one-second SQLite accumulation, migration from the legacy `focustime.db`, desktop-entry resolution, Hyprland socket listening, and atomic JSON summary writes. |
| Shared solar logic | `desktopctl/src/solar.rs:40-202` resolves cached or GeoClue coordinates, compute sunrise/sunset with the NOAA-derived port, and expose `sun status` plus next-event selection. |
| Night-light CLI and helpers | `desktopctl/src/night_light.rs:15-318` adds the daemon-backed `desktopctl night-light {status,on,off,auto,toggle}` surface, the Unix-socket client helpers, fallback status reporting, and `hyprsunset` process inspection / start / stop helpers. |
| Daemon supervisor | `desktopctl/src/daemon/mod.rs:27-95` starts the focus tracker, solar scheduler, and Unix-socket server under one tokio runtime, sharing one night-light controller between the solar and socket tasks and coordinating clean shutdown on `SIGTERM` / `SIGINT`. |
| Night-light controller | `desktopctl/src/daemon/night_light.rs:14-165` stores the live `auto` / `on` / `off` mode, keeps the in-session manual temperature, derives the effective state from solar status, and remains the only live writer of `hyprsunset`. In `auto`, it also persists the scheduled `dark_hint` by calling `desktopctl/src/night_light.rs:169-175`, which in turn delegates to `desktopctl/src/theme/mod.rs:73-95`. |
| Solar scheduler | `desktopctl/src/daemon/solar.rs:8-49` replaces the old systemd timer script chain with an in-process scheduler that recomputes solar status immediately, sleeps until the next sunrise / sunset / 23:00 event or 2-hour repair tick, and asks the shared controller to reconcile the effective mode. |
| Socket server | `desktopctl/src/daemon/server.rs:18-147` serves newline-delimited JSON requests on `$XDG_RUNTIME_DIR/desktopctl.sock`, including the daemon-owned `night_light.status`, `night_light.set`, and `night_light.toggle` methods. |
| Existing helper ports | `desktopctl/src/brightness.rs`, `desktopctl/src/launch.rs`, and `desktopctl/src/portal.rs` remain the active ports for brightness stepping/dimming, Quickshell launch env export, and the directory picker helper. The brightness helpers now notify Quickshell through `qs ipc` (`desktopctl/src/brightness.rs:145-156`), and `desktopctl/src/portal.rs:14-167` now correlates portal responses to the `OpenFile` request handle before accepting a returned directory. |

## Repo Integration

| Surface | Current implementation |
| --- | --- |
| Nix overlay and package wiring | `system/configuration.nix:5-8` imports the `desktopctl` overlay, `system/configuration.nix:159-162` applies it globally, and `overlays/march-optimized.nix:167-170` optionally rebuilds `desktopctl` with march tuning. |
| Home Manager install and activation | `home/default.nix:37-49` adds `desktopctl` to `home.packages`, and `home/default.nix:323-327` runs `desktopctl theme sync` during Home Manager activation. |
| Quickshell settings host | `config/quickshell/popups/SettingsPopup.qml:128-245` reads theme state, scheme lists, and presets through `desktopctl theme ... --json`; `config/quickshell/DisplayService.qml:40-239` now reads daemon-owned night-light status and sends `desktopctl night-light ...` requests, while `config/quickshell/popups/SettingsPopup.qml:691-800` sends theme mutations through `desktopctl theme set`, `preset`, `save-preset`, and `delete-preset`. |
| Quickshell shell IPC | `config/quickshell/shell.qml:24-108` and `config/quickshell/shell.qml:380-415` route the shell-level `theme.apply` IPC path to `desktopctl theme ...` with argv-safe tokenization and failure reporting. |
| Hyprland autostart | `config/hypr/autostart.conf:4-12` launches `desktopctl daemon`, launches Quickshell through `desktopctl launch-quickshell`, and reapplies the persisted wallpaper via `desktopctl theme wallpaper` after `awww-daemon` starts. It no longer seeds any brightness cache. |
| Hyprland keybinds and idle hooks | `config/hypr/keybinds.conf:9-98` now uses descriptive `bindd` / `bindde` bindings around `desktopctl hypr toggle-float`, `desktopctl brightness`, `desktopctl night-light`, and `desktopctl launch-quickshell`; `config/hypr/hypridle.conf:7-12` uses `desktopctl brightness dim` / `restore`. |

## Migration Status

- The tracked Python theming entry point and session-script surfaces are gone:
  `themes/apply-theme`, `scripts/focus-daemon.py`, `scripts/sun-schedule`,
  `scripts/brightness-step.sh`, `scripts/dim-screen.sh`,
  `scripts/toggle-float.sh`, `scripts/launch-quickshell.sh`,
  `config/quickshell/scripts/dir-picker.py`, and `home/sun-schedule.nix` are
  no longer part of the repo.
- A `themes/lib/` directory can still reappear locally if stale Python bytecode
  artifacts are generated by an old checkout or tool cache, but it is no longer
  a tracked implementation surface.

## Verification

- A target-by-target audit compared `desktopctl theme target <name>` against the
  removed Python implementation for the 19 legacy migrated theme targets using
  the same theme JSON payload; no byte-level output differences remain there.
- `desktopctl/src/theme/targets/mod.rs:406-758` now contains regression tests
  that cover both metadata paths: loading the real `themes/colors/*.json` files
  to assert the centralized app-theme metadata used by `bat`,
  `snappy_switcher`, `vicinae`, and `vscode`, and a shared synthetic
  `gruvbox-dark` fixture that carries the same metadata for Python-format
  output assertions.
- `desktopctl/src/theme/targets/gtksourceview.rs:314-362` adds focused
  coverage for generated GtkSourceView XML and the current light/dark pairing
  policy used to set gedit's source-style keys.
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
