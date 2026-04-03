# Theming Architecture

## Scope

Current implementation map for the migrated Rust theming pipeline as of
2026-04-03.

## Runtime Surface

| Piece | Current implementation |
| --- | --- |
| CLI entry point | `desktopctl/src/main.rs:46-83` and `desktopctl/src/theme/mod.rs:61-447` implement the full `desktopctl theme` surface. |
| Schema | `desktopctl/src/theme/schema.rs:5-92` and `desktopctl/src/theme/schema.rs:245-422` define `ColorScheme`, `ThemeState`, field ordering, and the shared mono-font-size helpers. |
| Resolution | `desktopctl/src/theme/resolve.rs:11-224` resolves `themes/colors/` and `themes/state.json`, validates both JSON surfaces, and writes `state.json` back with stable pretty formatting. |
| JSON compatibility | `desktopctl/src/theme/json.rs:4-142` preserves Python-compatible object ordering and ASCII escaping for generated JSON files and `--json` CLI output. |
| Registry | `desktopctl/src/theme/targets/mod.rs:24-230` defines target metadata, hook surfaces, and the typed registry; `desktopctl/src/theme/targets/mod.rs:232-315` registers all migrated targets explicitly. |
| Orchestrator | `desktopctl/src/theme/orchestrator.rs:47-228` and `desktopctl/src/theme/orchestrator.rs:230-383` handle dependency selection, target ordering, file assembly, concat merges, post-write hooks, reload hooks, and sync-safe filtering. |

## CLI Surface

| Command group | Commands | Current behavior |
| --- | --- | --- |
| Apply scopes | `all`, `colors`, `fonts`, `wallpaper`, `cursor`, `sync`, `target` | `sync` limits execution to `sync_safe` targets and skips runtime-only hooks. |
| State mutation | `set`, `preset`, `save-preset`, `delete-preset` | `set` rewrites one key and applies only affected targets; `preset` merges a preset patch and applies all targets; preset files preserve ordered JSON formatting. |
| Inspection | `list-schemes`, `list-presets`, `status` | Human-readable text by default, with Quickshell-facing `--json` modes that return deterministic array/object shapes. |

## Registered Targets

| Assembly | Targets |
| --- | --- |
| `import` | `alacritty`, `tmux`, `zathura` |
| `standalone` | `bat`, `cursor`, `hypr_appearance`, `hyprland`, `neovide`, `neovim`, `qt`, `quickshell`, `spicetify` |
| `concat` | `ghostty`, `snappy_switcher`, `starship`, `vicinae`, `vscode` |
| `command` | `gtk`, `wallpaper` |

Targets with notable extra behavior:

| Target | Extra behavior beyond one generated file |
| --- | --- |
| `cursor` | `desktopctl/src/theme/targets/cursor.rs:153-221` writes cursor index files plus `~/.config/hypr/cursor.conf`, updates dconf, updates Hyprland cursor env, and imports cursor vars into the user environment. |
| `gtk` | `desktopctl/src/theme/targets/gtk.rs:5-71` is command-only and does all real work in `on_apply()` through dconf writes. |
| `qt` | `desktopctl/src/theme/targets/qt.rs:15-99` and the rest of the module mirror the palette into qt5ct, qt6ct, KDE, hyprqt6engine, Kvantum, Kate, and KWrite. |
| `quickshell` | `desktopctl/src/theme/targets/quickshell.rs:8-85` writes `GeneratedTheme.json` for shell colors and fonts with Python-compatible JSON formatting. |
| `spicetify` | `desktopctl/src/theme/targets/spicetify.rs` ensures theme scaffolding exists and runs `spicetify update` on apply. |
| `wallpaper` | `desktopctl/src/theme/targets/wallpaper.rs:13-220` preserves the old `lutgen` cache-key behavior and `awww` runtime side effects while remaining `sync_safe = false`. |

## Consumer Integration

| Consumer | Current integration |
| --- | --- |
| Home Manager | `home/default.nix:310-312` runs `desktopctl theme sync` after managed files are written so generated fragments exist before the next session. |
| Hyprland | `config/hypr/hyprland.conf` and `config/hypr/appearance.conf` source generated `colors.conf`, `cursor.conf`, and `appearance-theme.conf`. |
| Quickshell | `config/quickshell/Theme.qml:8-27` watches `~/.config/quickshell/GeneratedTheme.json`; `config/quickshell/popups/SettingsPopup.qml:158-223` and `config/quickshell/shell.qml:299-305` now call `desktopctl theme` instead of hardcoded repo scripts. |
| Neovim / Neovide | Generated `theme-state.json` and `neovide-theme.lua` are still written inside the Home Manager-symlinked `~/.config/nvim` tree. |
| Tool configs | Import or concat targets still write under `~/.config` or app-specific config paths, keeping repo-authored base files read-only. |

## Validation Notes

- The migration audit compared every target's generated output with the removed
  Python implementation and fixed the only observed mismatches in JSON ordering
  and CLI error text.
- `desktopctl theme list-schemes --json`, `list-presets --json`, and
  `status --json` now match the shapes consumed by Quickshell.
