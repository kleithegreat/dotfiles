# Theming Architecture

## Scope

Current implementation map for the migrated Rust theming pipeline as of
2026-04-08.

## Runtime Surface

| Piece | Current implementation |
| --- | --- |
| CLI entry point | `desktopctl/src/main.rs:46-83` and `desktopctl/src/theme/mod.rs:66-568` implement the full `desktopctl theme` surface. |
| Schema | `desktopctl/src/theme/schema.rs:121-580` defines `ColorScheme`, required `appearance`, centralized per-target app-theme metadata, `ThemeState`, canonical field ordering, compiled default theme-state values, and the shared mono-font-size helpers. |
| Resolution | `desktopctl/src/theme/resolve.rs:11-500` resolves `themes/colors/`, rejects schemes that omit `appearance`, persists theme state in the shared `desktopctl.db` `theme_state` table, imports legacy `themes/state.json` on first access, and serializes canonical JSON for CLI output. |
| JSON compatibility | `desktopctl/src/theme/json.rs:4-142` preserves Python-compatible object ordering and ASCII escaping for generated JSON files and `--json` CLI output. |
| Registry | `desktopctl/src/theme/targets/mod.rs:25-297` defines target metadata, hook surfaces, and the typed registry, and registers all current targets explicitly. |
| Orchestrator | `desktopctl/src/theme/orchestrator.rs:16-52`, `desktopctl/src/theme/orchestrator.rs:55-236`, `desktopctl/src/theme/orchestrator.rs:238-325`, and `desktopctl/src/theme/orchestrator.rs:517-520` handle dependency selection, target ordering, file assembly, atomic file replacement, concat merges, repo-relative `base_path` resolution, post-write hooks, reload hooks, and sync-safe filtering. The current dependency map now routes `font_size` changes back to `quickshell` and includes the GtkSourceView color fanout through `desktopctl/src/theme/orchestrator.rs:16-52` and `desktopctl/src/theme/orchestrator.rs:189-215`. |

## CLI Surface

| Command group | Commands | Current behavior |
| --- | --- | --- |
| Apply scopes | `all`, `colors`, `fonts`, `wallpaper`, `cursor`, `sync`, `target` | `sync` limits execution to `sync_safe` targets and skips runtime-only hooks. |
| State mutation | `set`, `preset`, `save-preset`, `delete-preset` | `set` rewrites one key, applies only affected targets, then persists on success; `preset` merges a preset patch, applies all targets, then persists on success; preset files preserve ordered JSON formatting and are atomically replaced. |
| Inspection | `list-schemes`, `list-presets`, `status` | Human-readable text by default, with Quickshell-facing `--json` modes that return deterministic array/object shapes and the canonical theme-state JSON order from SQLite-backed storage. |

## Registered Targets

| Assembly | Targets |
| --- | --- |
| `import` | `alacritty`, `tmux`, `zathura` |
| `standalone` | `bat`, `cursor`, `gtksourceview`, `hypr_appearance`, `hyprland`, `neovide`, `neovim`, `qt`, `quickshell`, `spicetify` |
| `concat` | `ghostty`, `snappy_switcher`, `starship`, `vicinae`, `vscode` |
| `command` | `gtk`, `wallpaper` |

Per-scheme theme-name translation now lives in `themes/colors/*.json` and is
surfaced through `ColorScheme` helpers in `desktopctl/src/theme/schema.rs:237-294`.
`desktopctl/src/theme/targets/bat.rs:1-20`,
`desktopctl/src/theme/targets/snappy_switcher.rs:11-94`,
`desktopctl/src/theme/targets/vicinae.rs:8-51`, and
`desktopctl/src/theme/targets/vscode.rs:9-100` now consume that shared metadata
instead of re-encoding family/variant match tables locally.

Targets with notable extra behavior:

| Target | Extra behavior beyond one generated file |
| --- | --- |
| `cursor` | `desktopctl/src/theme/targets/cursor.rs:153-221` writes cursor index files plus `~/.config/hypr/cursor.conf`, updates dconf, updates Hyprland cursor env, and imports cursor vars into the user environment. |
| `gtk` | `desktopctl/src/theme/targets/gtk.rs:5-72` is command-only and does all real work in `on_apply()` through dconf writes. |
| `gtksourceview` | `desktopctl/src/theme/targets/gtksourceview.rs:13-360` writes the current GtkSourceView scheme to `desktopctl-current.xml`, mirrors the rest of the repo scheme catalog into `~/.local/share/libgedit-gtksourceview-300/styles/desktopctl-*.xml`, and updates gedit's dark/light source-style dconf keys at runtime. |
| `qt` | `desktopctl/src/theme/targets/qt.rs:15-99` and `desktopctl/src/theme/targets/qt.rs:445-628` mirror the palette into qt5ct, qt6ct, KDE, hyprqt6engine, Kvantum, Kate, and KWrite, and use the centralized `ColorScheme.appearance` metadata when only dark/light asset selection is needed. |
| `quickshell` | `desktopctl/src/theme/targets/quickshell.rs:19-89` writes `GeneratedTheme.json` for shell colors and fonts with Python-compatible JSON formatting, emits both `family` and `systemFamily`, and derives `size`, `sizeSmall`, and `sizeLarge` from `ThemeState.font_size`. |
| `spicetify` | `desktopctl/src/theme/targets/spicetify.rs` ensures theme scaffolding exists and runs `spicetify update` on apply. |
| `wallpaper` | `desktopctl/src/theme/targets/wallpaper.rs:13-220` preserves the old `lutgen` cache-key behavior and `awww` runtime side effects while remaining `sync_safe = false`. |

## Consumer Integration

| Consumer | Current integration |
| --- | --- |
| Home Manager | `home/default.nix:329-332` runs `desktopctl theme sync` after managed files are written so generated fragments exist before the next session. |
| Gedit / GtkSourceView | The `gtksourceview` target writes generated styles into `~/.local/share/libgedit-gtksourceview-300/styles/` during sync-safe runs, then sets gedit's per-variant source-style dconf keys during runtime applies. |
| Hyprland | `config/hypr/hyprland.conf` and `config/hypr/appearance.conf` source generated `colors.conf`, `cursor.conf`, and `appearance-theme.conf`. `config/hypr/autostart.conf:12-13` now re-applies the wallpaper target from persisted theme state once `awww-daemon` is ready. |
| Quickshell | `config/quickshell/Theme.qml:9-23` watches the XDG-config-derived `GeneratedTheme.json` path; `config/quickshell/popups/SettingsPopup.qml:160-175`, `config/quickshell/popups/SettingsPopup.qml:209-292`, `config/quickshell/popups/SettingsPopup.qml:397-404`, `config/quickshell/popups/SettingsPopup.qml:741-815`, `config/quickshell/popups/SettingsPopup.qml:1067-1096`, and `config/quickshell/shell.qml:24-108`, `config/quickshell/shell.qml:395-414` call `desktopctl theme` through argv-safe command construction instead of hardcoded repo scripts. The settings host stages individual `theme set` writes optimistically, serializes queued `set` / `preset` requests, reloads or rolls back on process exit, and now consumes the richer `list-schemes --json` preview payload for the shared color-card selectors. The recursive Quickshell tree also carries one committed bootstrap snapshot at `config/quickshell/GeneratedTheme.json`, which activation/runtime theme applies overwrite in place. |
| Neovim / Neovide | Generated `theme-state.json` and `neovide-theme.lua` are still written inside the Home Manager-symlinked `~/.config/nvim` tree. |
| Tool configs | Import or concat targets still write under `~/.config` or app-specific config paths, keeping repo-authored base files read-only. Repo-authored concat bases now resolve through `paths::repo_root()` when the target declares a relative `base_path`. |

## Validation Notes

- The migration audit compared every target's generated output with the removed
  Python implementation and fixed the only observed mismatches in JSON ordering
  and CLI error text for the legacy target set.
- `desktopctl/src/theme/targets/mod.rs:406-758` now covers both regression-test
  paths: it loads the real `themes/colors/*.json` files to assert the
  centralized bat, snappy-switcher, Vicinae, and VS Code mappings across the
  full scheme catalog, and its shared synthetic `gruvbox-dark` fixture includes
  the same app-theme metadata so Python-format target tests exercise the
  centralized lookup path instead of falling back to defaults.
- `desktopctl/src/theme/targets/gtksourceview.rs:363-526` covers the generated
  GtkSourceView XML shape and the current family-pairing policy for gedit's
  dark/light source-style keys.
- `desktopctl/src/theme/targets/qt.rs:968-1017` covers the declared
  `appearance` behavior for KTextEditor and Kvantum dark/light asset selection.
- `desktopctl theme list-schemes --json`, `list-presets --json`, and
  `status --json` now match the shapes consumed by Quickshell, including the
  richer scheme-preview data used by the shared card selectors.
