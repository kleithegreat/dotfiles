# Theming Architecture

## Scope

Current implementation map for the migrated Rust theming pipeline as of
2026-04-09.

## Runtime Surface

| Piece | Current implementation |
| --- | --- |
| CLI entry point | `desktopctl/src/main.rs` and `desktopctl/src/theme/mod.rs` implement the full `desktopctl theme` surface. |
| Schema | `desktopctl/src/theme/schema.rs` defines `ColorScheme`, required `appearance`, centralized per-target app-theme metadata including KTextEditor theme names, `ThemeState`, canonical field ordering, compiled default theme-state values, the per-target system-font and mono-font offset contract, and the shared font-size / mono-font-size helpers. The default-state logic there still derives `dark_hint` from the default scheme's declared appearance instead of a detached constant. |
| Resolution | `desktopctl/src/theme/resolve.rs` resolves `themes/colors/`, rejects schemes that omit `appearance`, persists theme state in the shared `desktopctl.db` `theme_state` table, backfills missing required `ThemeState` keys from compiled defaults when older SQLite rows or legacy `themes/state.json` inputs are reused, imports the legacy JSON on first access, and serializes canonical JSON for CLI output. |
| JSON compatibility | `desktopctl/src/theme/json.rs` preserves Python-compatible object ordering and ASCII escaping for generated JSON files and `--json` CLI output. |
| Registry | `desktopctl/src/theme/targets/mod.rs` defines target metadata, hook surfaces, and the typed registry, and registers all 22 current targets explicitly. |
| Orchestrator | `desktopctl/src/theme/orchestrator.rs` handles dependency selection, target ordering, file assembly, atomic file replacement, concat merges, repo-relative `base_path` resolution, post-write hooks, reload hooks, and sync-safe filtering. The current dependency map routes `font_size`, `quickshell_font_size_offset`, `gtk_font_size_offset`, `qt_font_size_offset`, and `chromium_font_size_offset` back to the matching font consumers, keeps the GtkSourceView color fanout, and now includes OpenCode in the `color_scheme` fanout. |

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
| `concat` | `ghostty`, `opencode`, `snappy_switcher`, `starship`, `vicinae`, `vscode` |
| `command` | `chromium`, `gtk`, `wallpaper` |

Per-scheme theme-name translation now lives in `themes/colors/*.json` and is
surfaced through `ColorScheme` helpers in `desktopctl/src/theme/schema.rs`.
`desktopctl/src/theme/targets/bat.rs`,
`desktopctl/src/theme/targets/snappy_switcher.rs`,
`desktopctl/src/theme/targets/vicinae.rs`,
`desktopctl/src/theme/targets/vscode.rs`, and
`desktopctl/src/theme/targets/qt.rs` now consume that shared metadata
instead of re-encoding family/variant match tables locally.

Targets with notable extra behavior:

| Target | Extra behavior beyond one generated file |
| --- | --- |
| `chromium` | `desktopctl/src/theme/targets/chromium.rs` is command-only and patches each active Chromium profile's `Preferences` file in place by reading `Local State` `profile.last_active_profiles`, falling back to `Default`, recursively preserving unrelated profile prefs while setting the common-script web font families and writing the same integer default font sizes Chromium persists in its own settings UI. |
| `cursor` | `desktopctl/src/theme/targets/cursor.rs` writes cursor index files plus `~/.config/hypr/cursor.conf`, updates dconf, updates Hyprland cursor env, and imports cursor vars into the user environment. |
| `gtk` | `desktopctl/src/theme/targets/gtk.rs` is command-only and does all real work in `on_apply()` through dconf writes, now routing both the normal UI font and monospace font through the shared offset helpers. |
| `gtksourceview` | `desktopctl/src/theme/targets/gtksourceview.rs` writes the current GtkSourceView scheme to `desktopctl-current.xml`, mirrors the rest of the repo scheme catalog into `~/.local/share/libgedit-gtksourceview-300/styles/desktopctl-*.xml`, and updates gedit's dark/light source-style dconf keys at runtime. |
| `opencode` | `desktopctl/src/theme/targets/opencode.rs` concatenates the repo-owned OpenCode TUI base config from `config/opencode/base.json` into `~/.config/opencode/tui.json` to select the managed `desktopctl` theme, then persists `~/.config/opencode/themes/desktopctl.json` with an ASCII-safe palette mapped onto OpenCode's upstream theme schema. |
| `qt` | `desktopctl/src/theme/targets/qt.rs` mirrors the palette into qt5ct, qt6ct, KDE, hyprqt6engine, Kvantum, Kate, and KWrite. The target now writes `[Icons] Theme` into `kdeglobals`, drives KTextEditor from `ColorScheme.app_themes.ktexteditor`, uses the shared system-font and mono-font offset helpers for `hyprqt6engine`, and still uses the centralized `ColorScheme.appearance` metadata when only dark/light asset selection is needed. |
| `quickshell` | `desktopctl/src/theme/targets/quickshell.rs` writes `GeneratedTheme.json` for shell colors and fonts with Python-compatible JSON formatting, emits both `family` and `systemFamily`, and derives `size`, `sizeSmall`, and `sizeLarge` from `ThemeState.font_size + quickshell_font_size_offset`. |
| `spicetify` | `desktopctl/src/theme/targets/spicetify.rs` ensures theme scaffolding exists and runs `spicetify update` on apply. |
| `wallpaper` | `desktopctl/src/theme/targets/wallpaper.rs` preserves the old `lutgen` cache-key behavior and `awww` runtime side effects while remaining `sync_safe = false`. |

## Consumer Integration

| Consumer | Current integration |
| --- | --- |
| Home Manager | The `home.activation.applyTheme` hook in `home/default.nix` runs `desktopctl theme sync` after managed files are written so generated fragments exist before the next session. |
| Chromium | `desktopctl/src/theme/targets/chromium.rs` patches each active profile's `Preferences` file in place so Chromium web content picks up the managed system and mono font selections plus the same integer font-size prefs Chromium persists in its own settings UI. Browser chrome still follows GTK outside that prefs surface. |
| Gedit / GtkSourceView | The `gtksourceview` target writes generated styles into `~/.local/share/libgedit-gtksourceview-300/styles/` during sync-safe runs, then sets gedit's per-variant source-style dconf keys during runtime applies. |
| Hyprland | `config/hypr/hyprland.conf` and `config/hypr/appearance.conf` source generated `colors.conf`, `cursor.conf`, and `appearance-theme.conf`. The `awww-daemon` startup block in `config/hypr/autostart.conf` re-applies the wallpaper target from persisted theme state once the daemon is ready. |
| Quickshell | `config/quickshell/Theme.qml`, `config/quickshell/popups/SettingsPopup.qml`, the Fonts/Presets panes and preset editor, and `config/quickshell/shell.qml` call or route `desktopctl theme` through argv-safe command construction instead of hardcoded repo scripts. The settings host stages individual `theme set` writes optimistically, serializes queued `set` / `preset` requests, reloads or rolls back on process exit, now exposes the full system-font offset set (`quickshell`, `GTK`, `Qt`, `Chromium`) plus the full mono-offset set (including `neovide_mono_font_size_offset`) through the Fonts and Presets panes, labels the Chromium-specific system-font offset as `Chromium pages` because browser chrome still follows GTK, and keeps `icon_theme` and cursor controls on separate Icons and Mouse panes while consuming the richer `list-schemes --json` preview payload for the shared color-card selectors. The recursive Quickshell tree also carries one committed bootstrap snapshot at `config/quickshell/GeneratedTheme.json`, which activation/runtime theme applies overwrite in place. |
| Neovim / Neovide | Generated `theme-state.json` and `neovide-theme.lua` are still written inside the Home Manager-symlinked `~/.config/nvim` tree. |
| OpenCode | `desktopctl/src/theme/targets/opencode.rs` and `config/opencode/base.json` now generate the global `~/.config/opencode/tui.json` theme selection plus `~/.config/opencode/themes/desktopctl.json`. The target is intentionally color-only because upstream OpenCode TUI theming consumes a theme name plus theme-color JSON, and project-local OpenCode config layers can still override the global `desktopctl` theme by name. |
| Tool configs | Import or concat targets still write under `~/.config` or app-specific config paths, keeping repo-authored base files read-only. Repo-authored concat bases now resolve through `paths::repo_root()` when the target declares a relative `base_path`. |

## Validation Notes

- The migration audit compared every target's generated output with the removed
  Python implementation and fixed the only observed mismatches in JSON ordering
  and CLI error text for the legacy target set.
- The regression tests in `desktopctl/src/theme/targets/mod.rs` now cover both regression-test
  paths: it loads the real `themes/colors/*.json` files to assert the
  centralized bat, snappy-switcher, Vicinae, and VS Code mappings across the
  full scheme catalog, and its shared synthetic `gruvbox-dark` fixture includes
  the same app-theme metadata, including the KTextEditor name, so Python-format
  target tests exercise the centralized lookup path instead of falling back to
  defaults.
- The tests in `desktopctl/src/theme/resolve.rs` cover default seeding, unknown
  field round-trips, upgrade-time backfill for older `theme_state` SQLite rows,
  and legacy `themes/state.json` imports that are missing newer required keys.
- The tests in `desktopctl/src/theme/targets/gtksourceview.rs` cover the generated
  GtkSourceView XML shape and the current family-pairing policy for gedit's
  dark/light source-style keys.
- The tests in `desktopctl/src/theme/mod.rs` cover the rule that `color_scheme`
  changes realign `dark_hint` with scheme appearance before persistence.
- The tests in `desktopctl/src/theme/targets/chromium.rs` cover active-profile
  selection from `Local State`, fallback to `Default`, recursive Chromium prefs
  merging, Chromium-prefs-sized font writes, and per-target font-size offsets.
- The tests in `desktopctl/src/theme/targets/opencode.rs` cover the generated
  OpenCode theme-file shape, ASCII-safe JSON rendering for upstream theme
  names, and atomic replacement of the generated custom-theme file, while
  the tests in `desktopctl/src/theme/orchestrator.rs` cover the OpenCode
  `color_scheme` dependency fanout.
- The tests in `desktopctl/src/theme/targets/qt.rs` cover the declared
  KTextEditor theme metadata and Kvantum dark/light asset selection behavior.
- `desktopctl theme list-schemes --json`, `list-presets --json`, and
  `status --json` now match the shapes consumed by Quickshell, including the
  richer scheme-preview data used by the shared card selectors.
