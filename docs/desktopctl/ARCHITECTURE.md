# desktopctl Architecture

## Scope

Current implementation state for the unified `desktopctl` binary and its repo
integration as of 2026-04-10.

## Current Crate Layout

| Piece | Current implementation |
| --- | --- |
| Crate manifest and packaging | `desktopctl/Cargo.toml:1-12` defines the binary crate; `desktopctl/default.nix:1-15`, `overlays/local-packages.nix:1-4`, and `flake.nix:63-74` package it as a flake-exposed Nix derivation. |
| CLI dispatch | `desktopctl/src/main.rs:16-323` defines the full clap tree for `daemon`, `theme`, `brightness`, `hypr`, `launch-quickshell`, `portal`, `night-light`, and `sun`, including the nested `hypr input status/set` surface, and routes each command to the live Rust implementation. |
| Shared path helpers | `desktopctl/src/paths.rs:6-66` resolves the repo root from `DESKTOPCTL_REPO` or `~/repos/dotfiles`, exposes `repo_path()` for repo-relative helper lookups, provides shared XDG home/runtime fallbacks, and exposes the shared `desktopctl.db` path. |
| Theme schema and validation | `desktopctl/src/theme/schema.rs:33-120`, `desktopctl/src/theme/schema.rs:405-620`, and `desktopctl/src/theme/resolve.rs:11-248` define the `ColorScheme` and `ThemeState` contract, including required scheme `appearance`, centralized app-theme metadata including KTextEditor theme names, compiled default theme-state values, canonical field ordering, per-target system-font and mono-font offsets, color-scheme loading, `theme_state` persistence with legacy `themes/state.json` import support, and additive-schema backfill for older persisted state rows that are missing newer required keys. `desktopctl/src/theme/schema.rs:444-485` now derives the default `dark_hint` from the default color scheme's declared appearance. |
| Theme JSON compatibility | `desktopctl/src/theme/json.rs:4-142` implements Python-style JSON rendering, including preserved object order, 2-space indentation, compact object spacing, and `ensure_ascii=True` escaping used by generated JSON targets and Quickshell-facing CLI output. |
| Theme CLI surface | `desktopctl/src/theme/mod.rs:67-573` implements the current `desktopctl theme` command surface, including `all`, `sync`, scoped apply commands, `set`, `preset`, preset-file management, and `status` / `list-*` inspection output. `desktopctl/src/theme/mod.rs:438-507` emits richer `theme list-schemes --json` preview objects for Quickshell, including identity, appearance, named colors, bright variants, and the 16-color terminal palette. `desktopctl/src/theme/mod.rs:75-96` still persists and applies `dark_hint` directly through the theming module, `desktopctl/src/theme/mod.rs:322-396` keeps `theme set dark_hint ...` and explicit preset `dark_hint` values on that same direct path, and `desktopctl/src/theme/mod.rs:614-673` now realigns `dark_hint` to scheme appearance whenever `color_scheme` changes without an explicit override. |
| Theme orchestration | `desktopctl/src/theme/orchestrator.rs:16-68`, `desktopctl/src/theme/orchestrator.rs:77-235`, `desktopctl/src/theme/orchestrator.rs:237-324`, and `desktopctl/src/theme/orchestrator.rs:526-541` own generated-file headers, assembly strategies, sync-safe filtering, dependency selection, ordered target application, atomic file replacement, concat merges, repo-relative base-path resolution, post-write hooks, and best-effort runtime reloads. The current dependency map includes both `quickshell` and `gtksourceview` in the color-fanout tables and now routes the per-target system-font offsets plus Chromium font fanout through `desktopctl/src/theme/orchestrator.rs:16-68` and `desktopctl/src/theme/orchestrator.rs:191-223`. |
| Theme target registry | `desktopctl/src/theme/targets/mod.rs:26-305` replaces Python auto-discovery with a typed registry and hand-registered target set for all 21 current theme targets. |
| Theme targets | File-writing targets live under `desktopctl/src/theme/targets/*.rs`; `desktopctl/src/theme/targets/bat.rs:1-20`, `desktopctl/src/theme/targets/snappy_switcher.rs:11-94`, `desktopctl/src/theme/targets/vicinae.rs:8-51`, `desktopctl/src/theme/targets/vscode.rs:9-100`, and `desktopctl/src/theme/targets/qt.rs:448-490` read per-scheme app metadata from `ColorScheme`. The command-only `desktopctl/src/theme/targets/chromium.rs:9-226` target now patches the default Chromium profile prefs in place for web-font settings, converting point-based theme sizes into Chromium CSS-pixel prefs while preserving unrelated keys. The concat targets still declare repo-relative `base_path` values instead of `~/repos/dotfiles/...`, and `desktopctl/src/theme/targets/qt.rs:82-99`, `desktopctl/src/theme/targets/qt.rs:385-490`, and `desktopctl/src/theme/targets/qt.rs:544-629` write KDE icon-theme state into `kdeglobals`, sync Kate/KWrite to scheme-declared KTextEditor theme names, and use declared `appearance` for light/dark-only Kvantum asset selection. Other notable runtime-heavy ports include `desktopctl/src/theme/targets/cursor.rs:11-221`, `desktopctl/src/theme/targets/gtk.rs:5-75`, `desktopctl/src/theme/targets/gtksourceview.rs:13-360`, `desktopctl/src/theme/targets/quickshell.rs:19-89`, and `desktopctl/src/theme/targets/wallpaper.rs:13-220`. |
| Hyprland helpers | `desktopctl/src/hypr.rs:25-190` now covers both window helpers and live `hyprctl keyword` calls, while `desktopctl/src/hypr.rs:278-369` layers `~/.config/hypr/input.conf` defaults with the generated `input-runtime.conf` override file, atomically rewrites that file, and renders the persisted input block used by the Mouse settings page. `desktopctl/src/hypr.rs:490-557` adds focused tests for the parser, generated file format, and managed-input value parsing helpers. Socket lookup still prefers the current `HYPRLAND_INSTANCE_SIGNATURE`, falls back to `/tmp/hypr/<sig>/.socket2.sock`, and otherwise picks the newest discovered socket under the runtime or `/tmp/hypr` trees (`desktopctl/src/hypr.rs:192-276`). |
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
| Nix overlay and package wiring | `system/configuration.nix:5-9` imports the local-packages overlay, `system/configuration.nix:198-202` applies it globally, and `overlays/march-optimized.nix:167-169` optionally rebuilds `desktopctl` with march tuning. |
| Home Manager install and activation | `home/default.nix:38-52` adds `desktopctl` to `home.packages`, and `home/default.nix:332-336` now bootstraps `~/.config/hypr/input-runtime.conf` before running `desktopctl theme sync` during Home Manager activation. |
| Quickshell settings host | `config/quickshell/popups/SettingsPopup.qml:174-203` and `config/quickshell/popups/SettingsPopup.qml:338-385` load theme state plus shared mouse defaults through `desktopctl theme ... --json` and `desktopctl hypr input status --json`, while `config/quickshell/DisplayService.qml:40-239` reads daemon-owned night-light status and sends `desktopctl night-light ...` requests. `config/quickshell/popups/SettingsPopup.qml:832-1006` and `config/quickshell/popups/SettingsPopup.qml:1318-1331` now serialize both theme mutations and `desktopctl hypr input set ...` writes, including the split Icons page and the expanded Mouse page. |
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
- `desktopctl/src/theme/targets/mod.rs:307-788` now contains regression tests
  that cover both metadata paths: loading the real `themes/colors/*.json` files
  to assert the centralized app-theme metadata used by `bat`,
  `snappy_switcher`, `vicinae`, and `vscode`, and a shared synthetic
  `gruvbox-dark` fixture that carries the same metadata, including the
  KTextEditor name, for Python-format output assertions.
- `desktopctl/src/theme/targets/gtksourceview.rs:363-526` adds focused
  coverage for generated GtkSourceView XML and the current light/dark pairing
  policy used to set gedit's source-style keys.
- `desktopctl/src/theme/mod.rs:614-673` and
  `desktopctl/src/theme/mod.rs:1196-1202` add focused coverage for
  `color_scheme`-driven `dark_hint` normalization.
- `desktopctl/src/theme/resolve.rs:418-692` adds focused coverage for default
  state seeding, unknown-field round-trips, and upgrade-time backfill for both
  partial SQLite `theme_state` rows and legacy `themes/state.json` imports.
- `desktopctl/src/hypr.rs:490-557` adds focused coverage for the managed
  Hyprland input parser, the generated `input-runtime.conf` contents used by
  the Mouse settings flow, managed input-value parsers, and CLI-facing decimal
  formatting.
- `desktopctl/src/daemon/server.rs:149-249` now covers the socket protocol's
  request deserialization defaults, newline handling, `ping` success envelope,
  invalid-request and invalid-param errors, and unsupported-method errors
  without binding a filesystem socket.
- `desktopctl/src/brightness.rs:219-263` now covers the gamma-based
  raw/perceived conversion helpers, perceptual-step clamping, and zero-max
  rejection. The `dim`/`restore` subprocess choreography in
  `desktopctl/src/brightness.rs:45-103` remains side-effect-coupled and would
  need a smaller pure helper to unit-test directly.
- The `toggle-float` resize/center behavior in
  `desktopctl/src/hypr.rs:176-189` is still only expressed as a
  `hyprctl --batch` command string, so geometry-level assertions would require
  a pure helper.
- `desktopctl/src/portal.rs:244-316` now covers request-handle extraction,
  handle matching, response-finished detection, selected-path URI decoding, and
  invalid percent-escape rejection. The live `busctl` / `dbus-monitor`
  orchestration in `desktopctl/src/portal.rs:14-110` remains process-coupled.
- `desktopctl/src/solar.rs:268-348`,
  `desktopctl/src/daemon/solar.rs:51-70`, and
  `desktopctl/src/daemon/night_light.rs:168-233` now cover sunrise/sunset
  ordering, pre-sunrise and post-sunset schedule transitions, cached
  coordinate resolution, scheduler sleep math, and the controller's
  auto/manual desired-state mapping.
- `desktopctl/src/night_light.rs:321-427` now covers request-envelope
  serialization, response-envelope decoding, `socket_unavailable()`
  classification, and the existing temperature parsing / normalization helpers.
- `desktopctl/src/launch.rs:110-171` now covers `cursor.conf` parsing, file
  override precedence over inherited environment values, and the printable env
  export used by `launch-quickshell --print-env`.
- `desktopctl/src/paths.rs:85-210` plus
  `desktopctl/src/test_support.rs:1-72` now cover repo-root precedence,
  XDG-home and runtime-dir fallback behavior, database-path creation, and the
  serialized env-mutation scaffolding needed for those tests.
- `desktopctl/src/theme/targets/chromium.rs:148-226` adds focused coverage for
  recursive Chromium prefs merging, point-to-CSS-pixel font-size conversion,
  and per-target font-size offsets.
- `desktopctl/src/theme/targets/qt.rs:967-1023` adds scheme-metadata and
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
