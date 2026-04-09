# Theming Architecture

## Scope

Current implementation map for the migrated Rust theming pipeline as of
2026-04-09.

## Runtime Surface

| Piece | Current implementation |
| --- | --- |
| CLI entry point | `desktopctl/src/main.rs:46-83` and `desktopctl/src/theme/mod.rs:66-572` implement the full `desktopctl theme` surface. |
| Schema | `desktopctl/src/theme/schema.rs:33-106` and `desktopctl/src/theme/schema.rs:395-585` define `ColorScheme`, required `appearance`, centralized per-target app-theme metadata including KTextEditor theme names, `ThemeState`, canonical field ordering, compiled default theme-state values, the new `quickshell_font_size_offset` contract, and the shared font-size / mono-font-size helpers. `desktopctl/src/theme/schema.rs:432-469` still derives the default `dark_hint` from the default scheme's declared appearance instead of a detached constant. |
| Resolution | `desktopctl/src/theme/resolve.rs:11-500` resolves `themes/colors/`, rejects schemes that omit `appearance`, persists theme state in the shared `desktopctl.db` `theme_state` table, imports legacy `themes/state.json` on first access, and serializes canonical JSON for CLI output. |
| JSON compatibility | `desktopctl/src/theme/json.rs:4-142` preserves Python-compatible object ordering and ASCII escaping for generated JSON files and `--json` CLI output. |
| Registry | `desktopctl/src/theme/targets/mod.rs:25-297` defines target metadata, hook surfaces, and the typed registry, and registers all current targets explicitly. |
| Orchestrator | `desktopctl/src/theme/orchestrator.rs:35-53`, `desktopctl/src/theme/orchestrator.rs:55-236`, `desktopctl/src/theme/orchestrator.rs:238-325`, and `desktopctl/src/theme/orchestrator.rs:517-520` handle dependency selection, target ordering, file assembly, atomic file replacement, concat merges, repo-relative `base_path` resolution, post-write hooks, reload hooks, and sync-safe filtering. The current dependency map routes both `font_size` and `quickshell_font_size_offset` back to `quickshell`, and still includes the GtkSourceView color fanout through `desktopctl/src/theme/orchestrator.rs:35-53` and `desktopctl/src/theme/orchestrator.rs:189-215`. |

## CLI Surface

| Command group | Commands | Current behavior |
| --- | --- | --- |
| Apply scopes | `all`, `colors`, `fonts`, `wallpaper`, `cursor`, `sync`, `target` | `sync` limits execution to `sync_safe` targets and skips runtime-only hooks. |
| State mutation | `set`, `preset`, `save-preset`, `delete-preset` | `set` rewrites one key, applies only affected targets, then persists on success; `theme set color_scheme ...` also normalizes `dark_hint` to the selected scheme appearance before validation. `preset` merges a preset patch, applies all targets, then persists on success; presets that change `color_scheme` but omit `dark_hint` inherit the scheme appearance before apply, while explicit preset `dark_hint` values still take the direct theming path. Preset files preserve ordered JSON formatting and are atomically replaced. |
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
`desktopctl/src/theme/targets/vicinae.rs:8-51`,
`desktopctl/src/theme/targets/vscode.rs:9-100`, and
`desktopctl/src/theme/targets/qt.rs:447-489` now consume that shared metadata
instead of re-encoding family/variant match tables locally.

Targets with notable extra behavior:

| Target | Extra behavior beyond one generated file |
| --- | --- |
| `cursor` | `desktopctl/src/theme/targets/cursor.rs:153-221` writes cursor index files plus `~/.config/hypr/cursor.conf`, updates dconf, updates Hyprland cursor env, and imports cursor vars into the user environment. |
| `gtk` | `desktopctl/src/theme/targets/gtk.rs:5-72` is command-only and does all real work in `on_apply()` through dconf writes. |
| `gtksourceview` | `desktopctl/src/theme/targets/gtksourceview.rs:13-360` writes the current GtkSourceView scheme to `desktopctl-current.xml`, mirrors the rest of the repo scheme catalog into `~/.local/share/libgedit-gtksourceview-300/styles/desktopctl-*.xml`, and updates gedit's dark/light source-style dconf keys at runtime. |
| `qt` | `desktopctl/src/theme/targets/qt.rs:15-99`, `desktopctl/src/theme/targets/qt.rs:385-489`, and `desktopctl/src/theme/targets/qt.rs:543-628` mirror the palette into qt5ct, qt6ct, KDE, hyprqt6engine, Kvantum, Kate, and KWrite. The target now writes `[Icons] Theme` into `kdeglobals`, drives KTextEditor from `ColorScheme.app_themes.ktexteditor`, and still uses the centralized `ColorScheme.appearance` metadata when only dark/light asset selection is needed. |
| `quickshell` | `desktopctl/src/theme/targets/quickshell.rs:19-89` writes `GeneratedTheme.json` for shell colors and fonts with Python-compatible JSON formatting, emits both `family` and `systemFamily`, and derives `size`, `sizeSmall`, and `sizeLarge` from `ThemeState.font_size + quickshell_font_size_offset`. |
| `spicetify` | `desktopctl/src/theme/targets/spicetify.rs` ensures theme scaffolding exists and runs `spicetify update` on apply. |
| `wallpaper` | `desktopctl/src/theme/targets/wallpaper.rs:13-220` preserves the old `lutgen` cache-key behavior and `awww` runtime side effects while remaining `sync_safe = false`. |

## Consumer Integration

| Consumer | Current integration |
| --- | --- |
| Home Manager | `home/default.nix:329-332` runs `desktopctl theme sync` after managed files are written so generated fragments exist before the next session. |
| Gedit / GtkSourceView | The `gtksourceview` target writes generated styles into `~/.local/share/libgedit-gtksourceview-300/styles/` during sync-safe runs, then sets gedit's per-variant source-style dconf keys during runtime applies. |
| Hyprland | `config/hypr/hyprland.conf` and `config/hypr/appearance.conf` source generated `colors.conf`, `cursor.conf`, and `appearance-theme.conf`. `config/hypr/autostart.conf:12-13` now re-applies the wallpaper target from persisted theme state once `awww-daemon` is ready. |
| Quickshell | `config/quickshell/Theme.qml:9-23` watches the XDG-config-derived `GeneratedTheme.json` path; `config/quickshell/popups/SettingsPopup.qml:182-248`, `config/quickshell/popups/SettingsPopup.qml:252-292`, `config/quickshell/popups/SettingsPopup.qml:401-404`, `config/quickshell/popups/SettingsPopup.qml:741-800`, `config/quickshell/popups/SettingsPopup.qml:52-61`, `config/quickshell/popups/SettingsPopup.qml:1074-1081`, `config/quickshell/popups/SettingsPopup.qml:1109-1114`, `config/quickshell/popups/settings/SettingsFontsPane.qml:216-315`, `config/quickshell/popups/settings/SettingsFontsPane.qml:319-510`, `config/quickshell/popups/settings/SettingsPresetsPane.qml:13-43`, `config/quickshell/popups/settings/SettingsPresetsPane.qml:138-174`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:13-18`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:838-1018`, `config/quickshell/popups/settings/SettingsPresetEditor.qml:1152-1178`, and `config/quickshell/shell.qml:24-108`, `config/quickshell/shell.qml:395-414` call or route `desktopctl theme` through argv-safe command construction instead of hardcoded repo scripts. The settings host stages individual `theme set` writes optimistically, serializes queued `set` / `preset` requests, reloads or rolls back on process exit, now exposes `quickshell_font_size_offset` plus the full mono-offset set (including `neovide_mono_font_size_offset`) through the Fonts and Presets panes, and keeps `icon_theme` and cursor controls on separate Icons and Mouse panes while consuming the richer `list-schemes --json` preview payload for the shared color-card selectors. The recursive Quickshell tree also carries one committed bootstrap snapshot at `config/quickshell/GeneratedTheme.json`, which activation/runtime theme applies overwrite in place. |
| Neovim / Neovide | Generated `theme-state.json` and `neovide-theme.lua` are still written inside the Home Manager-symlinked `~/.config/nvim` tree. |
| Tool configs | Import or concat targets still write under `~/.config` or app-specific config paths, keeping repo-authored base files read-only. Repo-authored concat bases now resolve through `paths::repo_root()` when the target declares a relative `base_path`. |

## Validation Notes

- The migration audit compared every target's generated output with the removed
  Python implementation and fixed the only observed mismatches in JSON ordering
  and CLI error text for the legacy target set.
- `desktopctl/src/theme/targets/mod.rs:300-758` now covers both regression-test
  paths: it loads the real `themes/colors/*.json` files to assert the
  centralized bat, snappy-switcher, Vicinae, and VS Code mappings across the
  full scheme catalog, and its shared synthetic `gruvbox-dark` fixture includes
  the same app-theme metadata, including the KTextEditor name, so Python-format
  target tests exercise the centralized lookup path instead of falling back to
  defaults.
- `desktopctl/src/theme/targets/gtksourceview.rs:363-526` covers the generated
  GtkSourceView XML shape and the current family-pairing policy for gedit's
  dark/light source-style keys.
- `desktopctl/src/theme/mod.rs:613-672` and
  `desktopctl/src/theme/mod.rs:1195-1202` cover the rule that `color_scheme`
  changes realign `dark_hint` with scheme appearance before persistence.
- `desktopctl/src/theme/targets/qt.rs:966-1019` covers the declared
  KTextEditor theme metadata and Kvantum dark/light asset selection behavior.
- `desktopctl theme list-schemes --json`, `list-presets --json`, and
  `status --json` now match the shapes consumed by Quickshell, including the
  richer scheme-preview data used by the shared card selectors.
