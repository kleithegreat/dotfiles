# desktopctl Architecture

## Scope

Current implementation state for the Phase 0 foundation scaffold as of
2026-04-02.

## Current Crate Layout

| Piece | Current implementation |
| --- | --- |
| Crate manifest | `desktopctl/Cargo.toml:1-11` defines the binary crate, pins the Rust 2024 edition, and declares the Phase 0 dependency set: `clap`, `tokio`, `serde`, `serde_json`, and `rusqlite` with bundled SQLite. |
| CLI skeleton | `desktopctl/src/main.rs:6-192` defines the full clap command tree for `daemon`, `theme`, `brightness`, `hypr`, `launch-quickshell`, `portal`, and `sun`. Phase 0 stops after argument parsing: non-help subcommand invocations print a placeholder message and exit. |
| Path helpers | `desktopctl/src/paths.rs:9-75` resolves the repo root from `DESKTOPCTL_REPO` (with a compatibility fallback to `desktopctl_REPO`) or `$HOME/repos/dotfiles`, and provides helpers for `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`, and `XDG_RUNTIME_DIR`. |
| Hyprland helpers | `desktopctl/src/hypr.rs:12-103` defines `WindowInfo`, `active_window()`, `dispatch()`, `batch()`, `keyword()`, and `socket2_path()`, all implemented via `hyprctl` subprocess calls plus the Hyprland instance-signature path convention from `focus-daemon.py`. |

## CLI Surface

| Area | Current implementation |
| --- | --- |
| Theme CLI | `desktopctl/src/main.rs:46-112` mirrors the `themes/apply-theme` surface: `all`, `sync`, `colors`, `wallpaper`, `cursor`, `fonts`, `target`, `set`, `preset`, `save-preset`, `delete-preset`, `list-schemes`, `list-presets`, and `status`. The inspection commands already expose `--json` flags so the help text matches the spec's planned machine-readable modes. |
| Brightness CLI | `desktopctl/src/main.rs:114-140` defines `up`, `down`, `dim`, `restore`, and `seed`, with `--device <DEVICE>` present on the subcommands that operate on a concrete backlight device. |
| Hypr / launch / portal / sun | `desktopctl/src/main.rs:142-186` defines `hypr toggle-float`, `launch-quickshell --print-env`, `portal pick-directory`, and `sun status`. |

## Verification

- `XDG_CACHE_HOME=/tmp nix develop -c cargo build` succeeds from `desktopctl/`.
- `./target/debug/desktopctl --help` works.
- `./target/debug/desktopctl --version` works.
- Nested help for representative subcommands was verified with `theme --help`,
  `brightness up --help`, `theme status --help`, and
  `launch-quickshell --help`.
