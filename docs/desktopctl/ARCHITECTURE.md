# desktopctl Architecture

## Scope

Current implementation state for the Phase 1 shell-script port work as of
2026-04-03.

## Current Crate Layout

| Piece | Current implementation |
| --- | --- |
| Crate manifest | `desktopctl/Cargo.toml:1-11` defines the binary crate, pins the Rust 2024 edition, and carries the initial dependency set: `clap`, `tokio`, `serde`, `serde_json`, and `rusqlite` with bundled SQLite. |
| CLI dispatch | `desktopctl/src/main.rs:1-251` defines the full clap command tree for `daemon`, `theme`, `brightness`, `hypr`, `launch-quickshell`, `portal`, and `sun`, and now dispatches the Phase 1 `brightness`, `hypr`, `launch-quickshell`, and `portal` subcommands to real module logic while leaving `daemon`, `theme`, and `sun` as placeholders. |
| Path helpers | `desktopctl/src/paths.rs:9-75` resolves the repo root from `DESKTOPCTL_REPO` (with a compatibility fallback to `desktopctl_REPO`) or `$HOME/repos/dotfiles`, and provides helpers for `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`, and `XDG_RUNTIME_DIR`. |
| Brightness helpers | `desktopctl/src/brightness.rs:13-218` ports `brightness-step.sh` and `dim-screen.sh`: it auto-detects the backlight device from `/sys/class/backlight`, applies gamma-2.2 perceptual steps, saves dim PIDs to `/tmp/dim-screen.pid`, preserves restore state with `brightnessctl -s/-r`, and rewrites `/tmp/quickshell-brightness` after every brightness subcommand. |
| Hyprland helpers | `desktopctl/src/hypr.rs:14-119` keeps the shared `hyprctl` subprocess wrappers (`active_window()`, `dispatch()`, `batch()`, `keyword()`, `socket2_path()`) and now adds `toggle_float()` for the `hypr toggle-float` CLI. |
| Quickshell launch helper | `desktopctl/src/launch.rs:13-107` ports `launch-quickshell.sh`: it reads `cursor.conf`, clears `HYPRCURSOR_THEME` unless the file sets it, supports `--print-env`, resolves the repo root through `paths::repo_root()`, and `exec`s `quickshell -p <repo>/config/quickshell`. |
| Portal helper | `desktopctl/src/portal.rs:14-195` ports the directory picker by spawning `dbus-monitor` and `busctl`, applying the same 5-second call timeout and 120-second response wait as the Python script, then percent-decoding the returned `file://` URI before printing it. |

## CLI Surface

| Area | Current implementation |
| --- | --- |
| Theme CLI | `desktopctl/src/main.rs:43-116` still mirrors the `themes/apply-theme` surface: `all`, `sync`, `colors`, `wallpaper`, `cursor`, `fonts`, `target`, `set`, `preset`, `save-preset`, `delete-preset`, `list-schemes`, `list-presets`, and `status`. The parser is present, but execution still returns the Phase 0 placeholder error. |
| Brightness CLI | `desktopctl/src/main.rs:118-144` plus `desktopctl/src/brightness.rs:37-218` implement `up`, `down`, `dim`, `restore`, and `seed`. All five subcommands accept `--device <DEVICE>` overrides; otherwise the first `/sys/class/backlight` entry is used. |
| Hypr CLI | `desktopctl/src/main.rs:146-157` and `desktopctl/src/main.rs:228-231` dispatch `hypr toggle-float` to `desktopctl/src/hypr.rs:60-74`, which preserves the shell script's float-or-batch behavior. |
| Launch CLI | `desktopctl/src/main.rs:159-164` and `desktopctl/src/main.rs:207-214` dispatch `launch-quickshell` to `desktopctl/src/launch.rs:13-38`, including the `--print-env` mode. |
| Portal CLI | `desktopctl/src/main.rs:166-177` and `desktopctl/src/main.rs:234-243` dispatch `portal pick-directory` to `desktopctl/src/portal.rs:14-195`, which prints the selected directory path when the portal returns one. |
| Placeholder commands | `desktopctl/src/main.rs:212-214` still returns the shared placeholder error for `daemon`, `theme`, and `sun` execution paths. |

## Verification

- `XDG_CACHE_HOME=/tmp nix develop -c cargo build` succeeds from `desktopctl/`.
- The resulting binary links the new Phase 1 modules for `brightness`, `hypr`,
  `launch-quickshell`, and `portal`.
- Runtime integration against live Hyprland, brightnessctl hardware, and the
  desktop portal was not exercised in this architecture update because those
  paths require the user session services and devices to be present.
