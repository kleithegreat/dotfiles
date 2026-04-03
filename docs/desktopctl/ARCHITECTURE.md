# desktopctl Architecture

## Scope

Current implementation state for the Phase 4 theming foundation plus the Phase
3 daemon, focus, and solar work as of 2026-04-03.

## Current Crate Layout

| Piece | Current implementation |
| --- | --- |
| Crate manifest | `desktopctl/Cargo.toml:1-12` defines the binary crate, keeps the Rust 2024 edition, and now enables `serde_json`'s `preserve_order` feature alongside `chrono`, `clap`, `tokio`, `serde`, and `rusqlite` so theme-state saves and JSON concat targets can keep Python-compatible key ordering. |
| CLI dispatch | `desktopctl/src/main.rs:1-257` defines the full clap tree for `daemon`, `theme`, `brightness`, `hypr`, `launch-quickshell`, `portal`, and `sun`, now compiles the new `theme` module tree, dispatches `daemon` to the runtime supervisor, dispatches `sun status` to the shared solar module, and still leaves `theme` on the Phase 0 placeholder. |
| Path helpers | `desktopctl/src/paths.rs:9-75` resolves the repo root from `DESKTOPCTL_REPO` or `$HOME/repos/dotfiles`, and provides the shared XDG path fallbacks used by the daemon, solar code, launch helper, and legacy-theme compatibility call. |
| Theme schema | `desktopctl/src/theme/schema.rs:14-422` ports the Python theme dataclasses: `ColorScheme` keeps the nested `colors` JSON wire format through custom serde while exposing flat fields to Rust code, and `ThemeState` now preserves unknown keys via `#[serde(flatten)]`, exposes the mono-font-offset helper methods, and can rebuild `state.json` in Python field order. |
| Theme resolution | `desktopctl/src/theme/resolve.rs:11-265` resolves `themes/colors/` and `themes/state.json` under the repo root, validates color JSON and state JSON with the same required-key and type checks as the Python resolver, and writes `state.json` with stable 2-space pretty-printing plus a trailing newline. |
| Theme orchestrator | `desktopctl/src/theme/orchestrator.rs:14-491` ports the dependency map, generated-file header, all four assembly strategies (`import`, `standalone`, `concat`, `command`), JSON depth-1 concat merges, post-write `persist()` hooks, best-effort runtime reload hooks, `targets_for_key()`'s wallpaper special case, `SYNC_SAFE` filtering, and the Python target ordering that runs file writers before command targets. |
| Theme target registry | `desktopctl/src/theme/targets/mod.rs:4-234` replaces Python auto-discovery with a typed registry API: `Assembly`, `GeneratedContent`, `TargetMetadata`, a `Target` trait, a function-pointer-backed `FunctionTarget`, metadata validation, and an empty `build_registry()` placeholder ready for Phase 5 target modules to register themselves. |
| Hyprland helpers | `desktopctl/src/hypr.rs:27-88` keeps the shared `hyprctl` wrappers (`active_window()`, `dispatch()`, `batch()`, `keyword()`, `socket2_path()`) used by both `hypr toggle-float` and the daemon subsystems. |
| Focus tracker | `desktopctl/src/daemon/focus.rs:20-145`, `desktopctl/src/daemon/focus.rs:148-418`, `desktopctl/src/daemon/focus.rs:422-773` port `scripts/focus-daemon.py`: a one-second accumulator loop writes `daily_totals`, `hourly_totals`, and `minute_totals` in SQLite, a background listener follows `activewindow>>` events on Hyprland's `.socket2.sock`, desktop entries are indexed by `StartupWMClass` and file stem, and the summary is serialized to Python-compatible JSON before an atomic temp-file rename to `focustime_state.json`. |
| Shared solar module | `desktopctl/src/solar.rs:48-259` provides the NOAA `sun_times()` port, cached-location / `where-am-i` / hardcoded fallback resolution, current-state computation, next-event selection, and the human-readable `sun status` report used by the CLI. |
| Daemon supervisor | `desktopctl/src/daemon/mod.rs:19-100` builds a tokio runtime on demand for `desktopctl daemon`, spawns the focus tracker, solar scheduler, and socket server concurrently, and converts `SIGTERM` / `SIGINT` into a coordinated shutdown signal for all three tasks. |
| Solar scheduler | `desktopctl/src/daemon/solar.rs:11-115` recomputes solar status on a two-hour cadence or `SIGUSR1`, sleeps until the next sunrise / sunset / 23:00 dark-on event, starts or stops `hyprsunset`, and currently shells out to the legacy `themes/apply-theme set dark_hint ...` path because the Rust `theme` CLI is still a placeholder. |
| Socket server | `desktopctl/src/daemon/server.rs:16-94` binds `$XDG_RUNTIME_DIR/desktopctl.sock`, removes stale socket files on startup, accepts newline-delimited JSON requests, answers `ping` with `{"ok":true,"data":{"pong":true}}`, and returns structured errors for unsupported or invalid requests. |
| Existing Phase 1 ports | `desktopctl/src/brightness.rs:37-218`, `desktopctl/src/launch.rs:13-108`, and `desktopctl/src/portal.rs:14-195` remain the active ports for the shell-script and Python helpers completed before the daemon work. |

## CLI Surface

| Area | Current implementation |
| --- | --- |
| Theme CLI | `desktopctl/src/main.rs:46-82`, `desktopctl/src/main.rs:216-217`, and the new Phase 4 theme modules now mirror the `themes/apply-theme` surface and provide the schema/resolution/orchestrator foundation, but top-level execution still returns the shared placeholder error until Phase 6 wires the subcommands. |
| Daemon CLI | `desktopctl/src/main.rs:27-42`, `desktopctl/src/main.rs:206-217`, and `desktopctl/src/daemon/mod.rs:19-100` make `desktopctl daemon` the foreground entry point for the new tokio-based daemon. |
| Sun CLI | `desktopctl/src/main.rs:181-191`, `desktopctl/src/main.rs:248-251`, and `desktopctl/src/solar.rs:48-72` implement `desktopctl sun status` as an independent status computation path; it does not query the placeholder socket server yet. |
| Brightness CLI | `desktopctl/src/main.rs:120-146` plus `desktopctl/src/brightness.rs:37-218` still implement `up`, `down`, `dim`, `restore`, and `seed`, with optional `--device <DEVICE>` overrides. |
| Hypr CLI | `desktopctl/src/main.rs:148-159`, `desktopctl/src/main.rs:230-233`, and `desktopctl/src/hypr.rs:59-72` still dispatch `hypr toggle-float` to the shared Hyprland helpers. |
| Launch CLI | `desktopctl/src/main.rs:161-166`, `desktopctl/src/main.rs:212-213`, and `desktopctl/src/launch.rs:13-38` still implement `launch-quickshell --print-env` and the final `exec quickshell -p ...` handoff. |
| Portal CLI | `desktopctl/src/main.rs:168-179`, `desktopctl/src/main.rs:236-245`, and `desktopctl/src/portal.rs:14-195` still implement `portal pick-directory` with the `dbus-monitor` plus `busctl` subprocess strategy. |

## Verification

- `XDG_CACHE_HOME=/tmp nix develop -c cargo test` succeeds from `desktopctl/`; the Phase 4 tests cover dependency-map filtering, sync-safe target filtering, live deserialization of `themes/state.json` and `themes/colors/gruvbox-dark.json`, Python-matching `state.json` serialization, and unknown-field round-tripping.
- `./target/debug/desktopctl sun status` runs successfully and prints location, sunrise/sunset, current dark state, and next events using the shared Rust solar module.
- The full daemon was not exercised against a live Hyprland session in this update, so the focus socket listener, `hyprlock` detection, `hyprsunset` control, and legacy `apply-theme` compatibility path were verified by code inspection and compilation, not by an end-to-end session run.
