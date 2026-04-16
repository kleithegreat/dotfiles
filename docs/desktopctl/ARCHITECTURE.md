# desktopctl Architecture

## Scope

Current implementation state for the unified `desktopctl` binary and its repo
integration as of 2026-04-13.

## Current Crate Layout

| Piece | Current implementation |
| --- | --- |
| Crate manifest and packaging | `desktopctl/Cargo.toml` defines the binary crate; `desktopctl/default.nix`, `overlays/local-packages.nix`, and the `packages.x86_64-linux` export in `flake.nix` package it as a flake-exposed Nix derivation. |
| CLI dispatch | `desktopctl/src/main.rs` defines the full clap tree for `daemon`, `theme`, `brightness`, `hypr`, `launch-quickshell`, `portal`, `night-light`, and `sun`, including the nested `hypr input status/set` surface, the hyphen-prefixed value handling needed by `theme set ... -1` and `hypr input set sensitivity -0.1`, and the live Rust dispatch. |
| Shared path helpers | `desktopctl/src/paths.rs` resolves the repo root from `DESKTOPCTL_REPO` or `~/repos/dotfiles`, exposes `repo_path()` for repo-relative helper lookups, provides shared XDG home/runtime fallbacks, and exposes the shared `desktopctl.db` path. |
| Theme schema and validation | `desktopctl/src/theme/schema.rs` and `desktopctl/src/theme/resolve.rs` define the `ColorScheme` and `ThemeState` contract, including required scheme `appearance`, centralized app-theme metadata including KTextEditor theme names, compiled default theme-state values, canonical field ordering, per-target system-font and mono-font offsets, color-scheme loading, `theme_state` persistence with legacy `themes/state.json` import support, and additive-schema backfill for older persisted state rows that are missing newer required keys. The default-state logic in `desktopctl/src/theme/schema.rs` now derives the default `dark_hint` from the default color scheme's declared appearance. |
| Theme JSON compatibility | `desktopctl/src/theme/json.rs` implements Python-style JSON rendering, including preserved object order, 2-space indentation, compact object spacing, and `ensure_ascii=True` escaping used by generated JSON targets and Quickshell-facing CLI output. |
| Theme CLI surface | `desktopctl/src/theme/mod.rs` implements the current `desktopctl theme` command surface, including `all`, `sync`, scoped apply commands, `set`, `preset`, preset-file management, and `status` / `list-*` inspection output. The `list-schemes --json` path emits richer preview objects for Quickshell, including identity, appearance, named colors, bright variants, and the 16-color terminal palette. `set_dark_hint()`, `cmd_set()`, and `cmd_preset()` still keep `dark_hint` on the direct theming path, while the theme tests there now cover `color_scheme`-driven `dark_hint` realignment when no explicit override is supplied. |
| Theme orchestration | `desktopctl/src/theme/orchestrator.rs` owns generated-file headers, assembly strategies, sync-safe filtering, dependency selection, ordered target application, atomic file replacement, concat merges, repo-relative base-path resolution, post-write hooks, and best-effort runtime reloads. The current dependency map includes both `quickshell` and `gtksourceview` in the color-fanout tables, now includes `zsh` there as well, routes the active per-target system-font offsets there as well, and leaves the persisted legacy `chromium_font_size_offset` key without target fanout. |
| Theme target registry | `desktopctl/src/theme/targets/mod.rs` replaces Python auto-discovery with a typed registry and hand-registered target set for all 23 current theme targets. |
| Theme targets | File-writing targets live under `desktopctl/src/theme/targets/*.rs`; `desktopctl/src/theme/targets/bat.rs`, `desktopctl/src/theme/targets/snappy_switcher.rs`, `desktopctl/src/theme/targets/vicinae.rs`, `desktopctl/src/theme/targets/vscode.rs`, and `desktopctl/src/theme/targets/qt.rs` read per-scheme app metadata from `ColorScheme`. The command-only `desktopctl/src/theme/targets/chromium.rs` target now patches each active Chromium profile prefs file in place for web-font settings by reading `Local State` `profile.last_active_profiles`, falling back to `Default`, removing any previously managed page-size prefs so Chromium falls back to its own defaults, and preserving unrelated keys. The concat targets still declare repo-relative `base_path` values instead of `~/repos/dotfiles/...`, the `qt` target writes KDE icon-theme state into `kdeglobals`, syncs Kate/KWrite to scheme-declared KTextEditor theme names, and uses declared `appearance` for light/dark-only Kvantum asset selection, and the import-only `desktopctl/src/theme/targets/zsh.rs` target now writes `~/.config/zsh/theme-colors` with a contrast-checked autosuggestion color chosen from the scheme's neutral foreground ladder. Other notable runtime-heavy ports include the `cursor`, `gtk`, `gtksourceview`, `quickshell`, and `wallpaper` targets. |
| Hyprland helpers | `desktopctl/src/hypr.rs` now covers both window helpers and live `hyprctl keyword` calls, layers `~/.config/hypr/input.conf` defaults with the generated `input-runtime.conf` override file, atomically rewrites that file, and renders the persisted input block used by the Mouse settings page. The same file also carries focused tests for the parser, generated file format, managed-input value parsing helpers, and socket lookup, which still prefers the current `HYPRLAND_INSTANCE_SIGNATURE`, falls back to `/tmp/hypr/<sig>/.socket2.sock`, and otherwise picks the newest discovered socket under the runtime or `/tmp/hypr` trees. |
| Focus tracker | `desktopctl/src/daemon/focus.rs` implements the live focus subsystem: one-second SQLite accumulation, migration from the legacy `focustime.db`, desktop-entry resolution, Hyprland socket listening, and atomic JSON summary writes. |
| Shared solar logic | `desktopctl/src/solar.rs` resolves cached or GeoClue coordinates, computes sunrise/sunset with the NOAA-derived port, and exposes `sun status` plus next-event selection. |
| Night-light CLI and helpers | `desktopctl/src/night_light.rs` adds the daemon-backed `desktopctl night-light {status,on,off,auto,toggle}` surface, the Unix-socket client helpers, fallback status reporting, and `hyprsunset` process / IPC helpers. When `hyprsunset` is already running, temperature reads and writes now go through its `~/.hyprsunset.sock` IPC endpoint so manual temperature changes can update in place without tearing the filter down first. |
| Daemon supervisor | `desktopctl/src/daemon/mod.rs` starts the focus tracker, solar scheduler, and Unix-socket server under one tokio runtime, sharing one night-light controller between the solar and socket tasks and coordinating clean shutdown on `SIGTERM` / `SIGINT`. |
| Night-light controller | `desktopctl/src/daemon/night_light.rs` stores the live `auto` / `on` / `off` mode, keeps the in-session manual temperature, derives the effective state from solar status, and remains the only live writer of `hyprsunset`. In `auto`, it also persists the scheduled `dark_hint` through the helpers in `desktopctl/src/night_light.rs`, which delegate to `set_dark_hint()` in `desktopctl/src/theme/mod.rs`. The helper layer now prefers in-place `hyprsunset` IPC temperature updates before falling back to a process restart. |
| Solar scheduler | `desktopctl/src/daemon/solar.rs` replaces the old systemd timer script chain with an in-process scheduler that recomputes solar status immediately, sleeps until the next sunrise / sunset / 23:00 event or 2-hour repair tick, and asks the shared controller to reconcile the effective mode. |
| Socket server | `desktopctl/src/daemon/server.rs` serves newline-delimited JSON requests on `$XDG_RUNTIME_DIR/desktopctl.sock`, including the daemon-owned `night_light.status`, `night_light.set`, and `night_light.toggle` methods. |
| Existing helper ports | `desktopctl/src/brightness.rs`, `desktopctl/src/launch.rs`, and `desktopctl/src/portal.rs` remain the active ports for brightness stepping/dimming, Quickshell launch env export, and the directory picker helper. The brightness helpers now notify Quickshell through `qs ipc`, and `desktopctl/src/portal.rs` now correlates portal responses to the `OpenFile` request handle before accepting a returned directory. |

## Repo Integration

| Surface | Current implementation |
| --- | --- |
| Nix overlay and package wiring | The local `let` imports plus `nixpkgs.overlays` in `system/configuration.nix` wire in the local-packages overlay, and `overlays/march-optimized.nix` optionally rebuilds `desktopctl` with march tuning. |
| Home Manager install and activation | `home/default.nix` adds `desktopctl` to `home.packages`, and the `home.activation.applyTheme` hook now bootstraps `~/.config/hypr/input-runtime.conf` before running `desktopctl theme sync` during Home Manager activation. |
| Quickshell settings host | `config/quickshell/popups/SettingsPopup.qml` loads theme state plus shared mouse defaults through `desktopctl theme ... --json` and `desktopctl hypr input status --json`, while `config/quickshell/DisplayService.qml` reads daemon-owned night-light status and sends `desktopctl night-light ...` requests. `SettingsPopup.qml` also serializes both theme mutations and `desktopctl hypr input set ...` writes, including the split Icons page and the expanded Mouse page. |
| Quickshell shell IPC | The `tokenizeThemeArgs` helper plus `themeApplyProc` / `theme.apply` handler in `config/quickshell/shell.qml` route the shell-level IPC path to `desktopctl theme ...` with argv-safe tokenization and failure reporting. |
| Hyprland autostart | `config/hypr/autostart.conf` launches `desktopctl daemon`, launches Quickshell through `desktopctl launch-quickshell`, and reapplies the persisted wallpaper via `desktopctl theme wallpaper` after `awww-daemon` starts. It no longer seeds any brightness cache. |
| Hyprland keybinds and idle hooks | `config/hypr/keybinds.conf` now uses descriptive `bindd` / `bindde` bindings around `desktopctl hypr toggle-float`, `desktopctl brightness`, `desktopctl night-light`, and `desktopctl launch-quickshell`; `config/hypr/hypridle.conf` uses `desktopctl brightness dim` / `restore`. |

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
- `desktopctl/src/theme/targets/mod.rs` now contains regression tests
  that cover both metadata paths: loading the real `themes/colors/*.json` files
  to assert the centralized app-theme metadata used by `bat`,
  `snappy_switcher`, `vicinae`, and `vscode`, and a shared synthetic
  `gruvbox-dark` fixture that carries the same metadata, including the
  KTextEditor name, for Python-format output assertions.
- `desktopctl/src/theme/targets/gtksourceview.rs` adds focused
  coverage for generated GtkSourceView XML and the current light/dark pairing
  policy used to set gedit's source-style keys.
- `desktopctl/src/theme/mod.rs` adds focused coverage for
  `color_scheme`-driven `dark_hint` normalization.
- `desktopctl/src/theme/resolve.rs` adds focused coverage for default
  state seeding, unknown-field round-trips, and upgrade-time backfill for both
  partial SQLite `theme_state` rows and legacy `themes/state.json` imports.
- `desktopctl/src/hypr.rs` adds focused coverage for the managed
  Hyprland input parser, the generated `input-runtime.conf` contents used by
  the Mouse settings flow, managed input-value parsers, and CLI-facing decimal
  formatting.
- `desktopctl/src/daemon/server.rs` now covers the socket protocol's
  request deserialization defaults, newline handling, `ping` success envelope,
  invalid-request and invalid-param errors, and unsupported-method errors
  without binding a filesystem socket.
- `desktopctl/src/brightness.rs` now covers the gamma-based
  raw/perceived conversion helpers, perceptual-step clamping, and zero-max
  rejection. The `dim`/`restore` subprocess choreography in
  `desktopctl/src/brightness.rs` remains side-effect-coupled and would
  need a smaller pure helper to unit-test directly.
- The `toggle-float` resize/center behavior in
  `desktopctl/src/hypr.rs` is still only expressed as a
  `hyprctl --batch` command string, so geometry-level assertions would require
  a pure helper.
- `desktopctl/src/portal.rs` now covers request-handle extraction,
  handle matching, response-finished detection, selected-path URI decoding, and
  invalid percent-escape rejection. The live `busctl` / `dbus-monitor`
  orchestration in `desktopctl/src/portal.rs` remains process-coupled.
- `desktopctl/src/solar.rs`, `desktopctl/src/daemon/solar.rs`, and
  `desktopctl/src/daemon/night_light.rs` now cover sunrise/sunset
  ordering, pre-sunrise and post-sunset schedule transitions, cached
  coordinate resolution, scheduler sleep math, and the controller's
  auto/manual desired-state mapping.
- `desktopctl/src/night_light.rs` now covers request-envelope
  serialization, response-envelope decoding, `socket_unavailable()`
  classification, and the existing temperature parsing / normalization helpers.
- `desktopctl/src/launch.rs` now covers `cursor.conf` parsing, file
  override precedence over inherited environment values, and the printable env
  export used by `launch-quickshell --print-env`.
- `desktopctl/src/paths.rs` plus `desktopctl/src/test_support.rs` now cover
  repo-root precedence,
  XDG-home and runtime-dir fallback behavior, database-path creation, and the
  serialized env-mutation scaffolding needed for those tests.
- `desktopctl/src/theme/targets/chromium.rs` adds focused coverage for
  active-profile selection, fallback to `Default`, recursive Chromium prefs
  merging, web-font family writes, and removal of previously managed page-size
  prefs.
- `desktopctl/src/theme/targets/qt.rs` adds scheme-metadata and
  appearance coverage for the `qt` target's KTextEditor and Kvantum
  dark/light asset selection.
- `desktopctl/src/theme/targets/zsh.rs` now covers the repo's full scheme
  catalog to lock the autosuggestion-color fallback order across dark and light
  themes.
- The CLI parity audit covered `theme set`, `preset`, `save-preset`, and
  `delete-preset`, including exit codes, stdout/stderr text, and resulting
  theme-state JSON / preset JSON content. The only mismatch found was the
  invalid-JSON `save-preset` error string, which is now fixed in Rust.
- The Quickshell-facing JSON modes now match the documented shapes and ordering:
  `theme status --json` mirrors the canonical theme-state JSON shape,
  `theme list-presets --json` matches the preset-file inventory, and
  `theme list-schemes --json` now returns the filename-ordered scheme-preview
  payload that QML consumes directly for its responsive color cards.
