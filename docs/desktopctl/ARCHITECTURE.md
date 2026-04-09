# desktopctl Architecture

## Scope

Current implementation state for the unified `desktopctl` binary and its repo
integration as of 2026-04-09.

## Current Crate Layout

| Piece | Current implementation |
| --- | --- |
| Crate manifest and packaging | `desktopctl/Cargo.toml:1-12` defines the binary crate; `desktopctl/default.nix:1-15`, `overlays/desktopctl.nix:1-3`, and `flake.nix:63-72` package it as a flake-exposed Nix derivation. |
| CLI dispatch | `desktopctl/src/main.rs:14-285` defines the full clap tree for `daemon`, `theme`, `brightness`, `hypr`, `launch-quickshell`, `portal`, `night-light`, and `sun`, and routes each command to the live Rust implementation. |
| Shared path helpers | `desktopctl/src/paths.rs:6-66` resolves the repo root from `DESKTOPCTL_REPO` or `~/repos/dotfiles`, exposes `repo_path()` for repo-relative helper lookups, provides shared XDG home/runtime fallbacks, and exposes the shared `desktopctl.db` path. |
| Theme schema and validation | `desktopctl/src/theme/schema.rs:121-580` and `desktopctl/src/theme/resolve.rs:11-500` define the `ColorScheme` and `ThemeState` contract, including required scheme `appearance`, centralized app-theme metadata including KTextEditor theme names, compiled default theme-state values, canonical field ordering, color-scheme loading, and `theme_state` persistence with legacy `themes/state.json` import support. `desktopctl/src/theme/schema.rs:423-466` now derives the default `dark_hint` from the default color scheme's declared appearance. |
| Theme JSON compatibility | `desktopctl/src/theme/json.rs:4-142` implements Python-style JSON rendering, including preserved object order, 2-space indentation, compact object spacing, and `ensure_ascii=True` escaping used by generated JSON targets and Quickshell-facing CLI output. |
| Theme CLI surface | `desktopctl/src/theme/mod.rs:66-572` implements the current `desktopctl theme` command surface, including `all`, `sync`, scoped apply commands, `set`, `preset`, preset-file management, and `status` / `list-*` inspection output. `desktopctl/src/theme/mod.rs:437-507` emits richer `theme list-schemes --json` preview objects for Quickshell, including identity, appearance, named colors, bright variants, and the 16-color terminal palette. `desktopctl/src/theme/mod.rs:74-96` still persists and applies `dark_hint` directly through the theming module, `desktopctl/src/theme/mod.rs:321-395` keeps `theme set dark_hint ...` and explicit preset `dark_hint` values on that same direct path, and `desktopctl/src/theme/mod.rs:613-672` now realigns `dark_hint` to scheme appearance whenever `color_scheme` changes without an explicit override. |
| Theme orchestration | `desktopctl/src/theme/orchestrator.rs:16-52`, `desktopctl/src/theme/orchestrator.rs:55-236`, `desktopctl/src/theme/orchestrator.rs:238-325`, and `desktopctl/src/theme/orchestrator.rs:517-520` own generated-file headers, assembly strategies, sync-safe filtering, dependency selection, ordered target application, atomic file replacement, concat merges, repo-relative base-path resolution, post-write hooks, and best-effort runtime reloads. The current dependency map includes both `quickshell` and `gtksourceview` in the color-fanout tables (`desktopctl/src/theme/orchestrator.rs:16-52`, `desktopctl/src/theme/orchestrator.rs:176-215`). |
| Theme target registry | `desktopctl/src/theme/targets/mod.rs:25-297` replaces Python auto-discovery with a typed registry and hand-registered target set for all 20 current theme targets. |
| Theme targets | File-writing targets live under `desktopctl/src/theme/targets/*.rs`; `desktopctl/src/theme/targets/bat.rs:1-20`, `desktopctl/src/theme/targets/snappy_switcher.rs:11-94`, `desktopctl/src/theme/targets/vicinae.rs:8-51`, `desktopctl/src/theme/targets/vscode.rs:9-100`, and `desktopctl/src/theme/targets/qt.rs:447-489` read per-scheme app metadata from `ColorScheme`. The concat targets now declare repo-relative `base_path` values instead of `~/repos/dotfiles/...`, and `desktopctl/src/theme/targets/qt.rs:82-99`, `desktopctl/src/theme/targets/qt.rs:385-489`, and `desktopctl/src/theme/targets/qt.rs:543-628` now write KDE icon-theme state into `kdeglobals`, sync Kate/KWrite to scheme-declared KTextEditor theme names, and use declared `appearance` for light/dark-only Kvantum asset selection. Other notable runtime-heavy ports include `desktopctl/src/theme/targets/cursor.rs:11-221`, `desktopctl/src/theme/targets/gtk.rs:5-72`, `desktopctl/src/theme/targets/gtksourceview.rs:13-360`, `desktopctl/src/theme/targets/quickshell.rs:19-89`, and `desktopctl/src/theme/targets/wallpaper.rs:13-220`. |
| Hyprland helpers | `desktopctl/src/hypr.rs:22-176` wraps `hyprctl activewindow -j`, `hyprctl dispatch`, `hyprctl --batch`, and `.socket2.sock` path discovery for both the Hypr CLI and the daemon. Socket lookup now prefers the current `HYPRLAND_INSTANCE_SIGNATURE`, falls back to `/tmp/hypr/<sig>/.socket2.sock`, and otherwise picks the newest discovered socket under the runtime or `/tmp/hypr` trees. |
| Focus tracker | `desktopctl/src/daemon/focus.rs:20-236`, `desktopctl/src/daemon/focus.rs:238-698`, and `desktopctl/src/daemon/focus.rs:700-902` implement the live focus subsystem: one-second SQLite accumulation, migration from the legacy `focustime.db`, desktop-entry resolution, Hyprland socket listening, and atomic JSON summary writes. |
| Shared solar logic | `desktopctl/src/solar.rs:40-202` resolves cached or GeoClue coordinates, compute sunrise/sunset with the NOAA-derived port, and expose `sun status` plus next-event selection. |
| Night-light CLI and helpers | `desktopctl/src/night_light.rs:15-318` adds the daemon-backed `desktopctl night-light {status,on,off,auto,toggle}` surface, the Unix-socket client helpers, fallback status reporting, and `hyprsunset` process inspection / start / stop helpers. |
| Daemon supervisor | `desktopctl/src/daemon/mod.rs:27-95` starts the focus tracker, solar scheduler, and Unix-socket server under one tokio runtime, sharing one night-light controller between the solar and socket tasks and coordinating clean shutdown on `SIGTERM` / `SIGINT`. |
| Night-light controller | `desktopctl/src/daemon/night_light.rs:14-165` stores the live `auto` / `on` / `off` mode, keeps the in-session manual temperature, derives the effective state from solar status, and remains the only live writer of `hyprsunset`. In `auto`, it also persists the scheduled `dark_hint` by calling `desktopctl/src/night_light.rs:169-175`, which in turn delegates to `desktopctl/src/theme/mod.rs:74-96`. |
| Solar scheduler | `desktopctl/src/daemon/solar.rs:8-49` replaces the old systemd timer script chain with an in-process scheduler that recomputes solar status immediately, sleeps until the next sunrise / sunset / 23:00 event or 2-hour repair tick, and asks the shared controller to reconcile the effective mode. |
| Socket server | `desktopctl/src/daemon/server.rs:18-147` serves newline-delimited JSON requests on `$XDG_RUNTIME_DIR/desktopctl.sock`, including the daemon-owned `night_light.status`, `night_light.set`, and `night_light.toggle` methods. |
| Existing helper ports | `desktopctl/src/brightness.rs`, `desktopctl/src/launch.rs`, and `desktopctl/src/portal.rs` remain the active ports for brightness stepping/dimming, Quickshell launch env export, and the directory picker helper. The brightness helpers now notify Quickshell through `qs ipc` (`desktopctl/src/brightness.rs:145-156`), and `desktopctl/src/portal.rs:14-167` now correlates portal responses to the `OpenFile` request handle before accepting a returned directory. |

## Repo Integration

| Surface | Current implementation |
| --- | --- |
| Nix overlay and package wiring | `system/configuration.nix:5-9` imports the `desktopctl` overlay, `system/configuration.nix:198-202` applies it globally, and `overlays/march-optimized.nix:167-169` optionally rebuilds `desktopctl` with march tuning. |
| Home Manager install and activation | `home/default.nix:38-52` adds `desktopctl` to `home.packages`, and `home/default.nix:332-335` runs `desktopctl theme sync` during Home Manager activation. |
| Quickshell settings host | `config/quickshell/popups/SettingsPopup.qml:160-175`, `config/quickshell/popups/SettingsPopup.qml:209-292`, and `config/quickshell/popups/SettingsPopup.qml:397-404` read theme state, scheme lists, and presets through `desktopctl theme ... --json`, normalize scheme previews into `colorFamilies`, and feed the shared color-card selectors. `config/quickshell/DisplayService.qml:40-239` now reads daemon-owned night-light status and sends `desktopctl night-light ...` requests, while `config/quickshell/popups/SettingsPopup.qml:706-815` and `config/quickshell/popups/SettingsPopup.qml:1067-1096` send theme mutations through `desktopctl theme set`, `preset`, `save-preset`, and `delete-preset`. |
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
- `desktopctl/src/theme/targets/mod.rs:300-758` now contains regression tests
  that cover both metadata paths: loading the real `themes/colors/*.json` files
  to assert the centralized app-theme metadata used by `bat`,
  `snappy_switcher`, `vicinae`, and `vscode`, and a shared synthetic
  `gruvbox-dark` fixture that carries the same metadata, including the
  KTextEditor name, for Python-format output assertions.
- `desktopctl/src/theme/targets/gtksourceview.rs:363-526` adds focused
  coverage for generated GtkSourceView XML and the current light/dark pairing
  policy used to set gedit's source-style keys.
- `desktopctl/src/theme/mod.rs:613-672` and
  `desktopctl/src/theme/mod.rs:1195-1202` add focused coverage for
  `color_scheme`-driven `dark_hint` normalization.
- `desktopctl/src/theme/targets/qt.rs:966-1019` adds scheme-metadata and
  appearance coverage for the `qt` target's KTextEditor and Kvantum
  dark/light asset selection.
- The CLI parity audit covered `theme set`, `preset`, `save-preset`, and
  `delete-preset`, including exit codes, stdout/stderr text, and resulting
  theme-state JSON / preset JSON content. The only mismatch found was the
  invalid-JSON `save-preset` error string, which is now fixed in Rust.
- The Quickshell-facing JSON modes now match the documented shapes and ordering:
  `theme status --json` mirrors the canonical theme-state JSON shape,
  `theme list-presets --json` matches the preset-file inventory, and
  `theme list-schemes --json` now returns the filename-ordered scheme-preview
  payload that QML consumes directly for its responsive color cards.
