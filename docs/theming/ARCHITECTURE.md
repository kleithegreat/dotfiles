# Theming Architecture

## Scope

Current implementation map for the migrated Rust theming pipeline as of
2026-04-19.

## Runtime Surface

| Piece | Current implementation |
| --- | --- |
| CLI entry point | `desktopctl/src/main.rs` and `desktopctl/src/theme/mod.rs` implement the full `desktopctl theme` surface. |
| Schema | `desktopctl/src/theme/schema.rs` defines `ColorScheme`, required `appearance`, centralized per-target app-theme metadata including KTextEditor theme names, `ThemeState`, canonical field ordering, compiled default theme-state values, the per-target system-font and mono-font offset contract, and the shared font-size / mono-font-size helpers. The default-state logic there still derives `dark_hint` from the default scheme's declared appearance instead of a detached constant. |
| Resolution | `desktopctl/src/theme/resolve.rs` resolves `themes/colors/`, rejects schemes that omit `appearance`, persists theme state in the shared `desktopctl.db` `theme_state` table, backfills missing required `ThemeState` keys from compiled defaults when older SQLite rows or legacy `themes/state.json` inputs are reused, canonicalizes known legacy string aliases such as older mono-font labels before validation/persistence, imports the legacy JSON on first access, and serializes canonical JSON for CLI output. |
| JSON compatibility | `desktopctl/src/theme/json.rs` preserves Python-compatible object ordering and ASCII escaping for generated JSON files and `--json` CLI output. |
| Registry | `desktopctl/src/theme/targets/mod.rs` defines target metadata, including primary generated outputs, additional hook-managed filesystem paths, and the consumed `ThemeState` key list for each target, exposes the hook surfaces, and registers all 23 current targets explicitly. |
| Orchestrator | `desktopctl/src/theme/orchestrator.rs` handles dependency selection, target ordering, file assembly, atomic file replacement, concat merges, repo-relative `base_path` resolution, post-write hooks, reload hooks, and sync-safe filtering. Color/font apply scopes plus per-key fanout now derive from each target's declared `TargetMetadata.state_keys`, with the existing wallpaper filter exception still handled there when `filter_wallpaper` is false. |

## CLI Surface

| Command group | Commands | Current behavior |
| --- | --- | --- |
| Apply scopes | `all`, `colors`, `fonts`, `wallpaper`, `cursor`, `sync`, `target` | `sync` limits execution to `sync_safe` targets and skips runtime-only hooks. |
| State mutation | `set`, `preset`, `save-preset`, `delete-preset` | `set` rewrites one key, applies only affected targets, then persists on success; `theme set color_scheme ...` now preserves the existing `dark_hint`. `preset` merges a preset patch, applies all targets, then persists on success; presets that omit `dark_hint` keep the current persisted hint even when they change `color_scheme`, while explicit preset `dark_hint` values still take the direct theming path. Preset files preserve ordered JSON formatting and are atomically replaced. |
| Inspection | `list-schemes`, `list-presets`, `status` | Human-readable text by default, with Quickshell-facing `--json` modes that return deterministic array/object shapes and the canonical theme-state JSON order from SQLite-backed storage. |

## Registered Targets

| Assembly | Targets |
| --- | --- |
| `import` | `alacritty`, `ghostty`, `tmux`, `vicinae`, `zathura`, `zsh` |
| `standalone` | `bat`, `cursor`, `gtksourceview`, `hypr_appearance`, `hyprland`, `neovide`, `neovim`, `qt`, `quickshell`, `spicetify` |
| `concat` | `opencode`, `snappy_switcher`, `starship`, `vscode` |
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
| `chromium` | `desktopctl/src/theme/targets/chromium.rs` is command-only and patches each active Chromium profile's `Preferences` file in place by reading `Local State` `profile.last_active_profiles`, falling back to `Default`, recursively preserving unrelated profile prefs while setting the common-script web font families and removing any previously managed page-size prefs so Chromium falls back to its own defaults. |
| `cursor` | `desktopctl/src/theme/targets/cursor.rs` writes cursor index files plus `~/.config/hypr/cursor.conf`, updates dconf, updates Hyprland cursor env, and imports cursor vars into the user environment. |
| `gtk` | `desktopctl/src/theme/targets/gtk.rs` is command-only and does all real work in `on_apply()` through dconf writes, now routing both the normal UI font and monospace font through the shared offset helpers. |
| `gtksourceview` | `desktopctl/src/theme/targets/gtksourceview.rs` writes the current GtkSourceView scheme to `desktopctl-current.xml`, mirrors the rest of the repo scheme catalog into `~/.local/share/libgedit-gtksourceview-300/styles/desktopctl-*.xml`, and updates gedit's dark/light source-style dconf keys at runtime. |
| `opencode` | `desktopctl/src/theme/targets/opencode.rs` concatenates the repo-owned OpenCode TUI base config from `config/opencode/base.json` into `~/.config/opencode/tui.json` to select the managed `desktopctl` theme, then persists `~/.config/opencode/themes/desktopctl.json` with an ASCII-safe palette mapped onto OpenCode's upstream theme schema. |
| `qt` | `desktopctl/src/theme/targets/qt.rs` mirrors the palette into qt5ct, qt6ct, KDE, hyprqt6engine, Kvantum, Kate, and KWrite. The target now writes `[Icons] Theme` into `kdeglobals`, drives KTextEditor from `ColorScheme.app_themes.ktexteditor`, uses the shared system-font and mono-font offset helpers for `hyprqt6engine`, and still uses the centralized `ColorScheme.appearance` metadata when only dark/light asset selection is needed. The shared system baseline in `system/configuration.nix` now supplies the runtime half of that contract by enabling NixOS `qt.enable`, exporting `QT_QPA_PLATFORMTHEME=hyprqt6engine`, keeping hyprqt6engine's nonstandard plugin root visible, installing qtct/Kvantum packages system-wide without a global `QT_STYLE_OVERRIDE`, and applying the shared fontconfig tuning that gives `system_font = "SF Pro"` RGB subpixel AA plus an `SF Pro Text` preference. |
| `quickshell` | `desktopctl/src/theme/targets/quickshell.rs` writes `GeneratedTheme.json` for shell colors and fonts with Python-compatible JSON formatting, emits both mono and system font families, and derives `size`, `sizeSmall`, and `sizeLarge` from `ThemeState.font_size + quickshell_font_size_offset`. |
| `spicetify` | `desktopctl/src/theme/targets/spicetify.rs` ensures theme scaffolding exists and runs `spicetify update` on apply. |
| `vicinae` | `desktopctl/src/theme/targets/vicinae.rs` now writes only `~/.config/vicinae/settings.theme.json`, while Home Manager deploys `config/vicinae/settings.json` as the base file that imports that fragment. Its `persist()` hook still writes custom TOML themes under `~/.local/share/vicinae/themes/` using the configured Vicinae theme IDs from `ColorScheme.app_themes.vicinae`. When a scheme declares a distinct Vicinae `light_name`, the hook loads that repo scheme too so the paired light file exists alongside the active theme. |
| `vscode` | `desktopctl/src/theme/targets/vscode.rs` merges the repo base settings with theme-owned color and font keys, and now prefers a `'<mono font> Mono', '<mono font>', monospace` stack for `terminal.integrated.fontFamily` when the selected font is a Nerd Font so prompt glyphs render reliably in the integrated terminal. |
| `wallpaper` | `desktopctl/src/theme/targets/wallpaper.rs` preserves the old `lutgen` cache-key behavior and `awww` runtime side effects while remaining `sync_safe = false`. |
| `zsh` | `desktopctl/src/theme/targets/zsh.rs` writes `~/.config/zsh/theme-colors` with a scheme-aware `ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE`, choosing the most-muted foreground tier that still clears the target contrast against `ColorScheme.bg`. |

## Consumer Integration

Nix/Home Manager ownership for base config deployment and activation is
documented in `docs/nix/ARCHITECTURE.md`.

| Consumer | Current integration |
| --- | --- |
| Home Manager | `home/xdg.nix` deploys the repo-owned base configs, and the `home.activation.applyTheme` hook in `home/default.nix` runs `desktopctl theme sync` after those managed files are written so generated fragments exist before the next session. |
| Chromium | `desktopctl/src/theme/targets/chromium.rs` patches each active profile's `Preferences` file in place so Chromium web content picks up the managed system and mono font selections while page sizes stay on Chromium defaults. Browser chrome still follows GTK outside that prefs surface. |
| Gedit / GtkSourceView | The `gtksourceview` target writes generated styles into `~/.local/share/libgedit-gtksourceview-300/styles/` during sync-safe runs, then sets gedit's per-variant source-style dconf keys during runtime applies. |
| Hyprland | `config/hypr/hyprland.conf` and `config/hypr/appearance.conf` source generated `colors.conf`, `cursor.conf`, and `appearance-theme.conf`. The `awww-daemon` startup block in `config/hypr/autostart.conf` re-applies the wallpaper target from persisted theme state once the daemon is ready. |
| Quickshell | `config/quickshell/Theme.qml`, `config/quickshell/popups/SettingsPopup.qml`, the Fonts/Presets panes, `config/quickshell/ShellOptions.qml`, and `config/quickshell/shell.qml` call or route `desktopctl theme` through argv-safe command construction instead of hardcoded repo scripts. The settings host still stages individual `theme set` writes optimistically, serializes queued `set` / `preset` requests, and reloads or rolls back on process exit. Shell-side pane structure, shared UI primitives, and the committed `config/quickshell/GeneratedTheme.json` bootstrap snapshot are documented in `docs/quickshell/ARCHITECTURE.md`. |
| Neovim / Neovide | Generated `theme-state.json` and `neovide-theme.lua` are still written inside the Home Manager-symlinked `~/.config/nvim` tree. |
| OpenCode | `desktopctl/src/theme/targets/opencode.rs` and `config/opencode/base.json` now generate the global `~/.config/opencode/tui.json` theme selection plus `~/.config/opencode/themes/desktopctl.json`. The target is intentionally color-only because upstream OpenCode TUI theming consumes a theme name plus theme-color JSON, and project-local OpenCode config layers can still override the global `desktopctl` theme by name. |
| Zsh | `home/shell.nix` sources `~/.config/zsh/theme-colors` from `programs.zsh.initContent`, while `desktopctl/src/theme/targets/zsh.rs` generates that fragment from the active `ColorScheme`. |
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
- The tests in `desktopctl/src/theme/targets/vicinae.rs` cover the generated
  `settings.theme.json` payload, the custom TOML theme-file shape, and atomic
  writes of the active plus paired light Vicinae themes under `XDG_DATA_HOME`.
- The tests in `desktopctl/src/theme/resolve.rs` cover default seeding, unknown
  field round-trips, upgrade-time backfill for older `theme_state` SQLite rows,
  and legacy `themes/state.json` imports that are missing newer required keys.
- The tests in `desktopctl/src/theme/targets/gtksourceview.rs` cover the generated
  GtkSourceView XML shape and the current family-pairing policy for gedit's
  dark/light source-style keys.
- The tests in `desktopctl/src/theme/mod.rs` cover the rule that
  `color_scheme` changes preserve an explicit `dark_hint` instead of
  realigning it to scheme appearance.
- The tests in `desktopctl/src/theme/targets/chromium.rs` cover active-profile
  selection from `Local State`, fallback to `Default`, recursive Chromium prefs
  merging, web-font family writes, and removal of previously managed page-size
  prefs.
- The tests in `desktopctl/src/theme/targets/opencode.rs` cover the generated
  OpenCode theme-file shape, ASCII-safe JSON rendering for upstream theme
  names, and atomic replacement of the generated custom-theme file, while
  the tests in `desktopctl/src/theme/orchestrator.rs` cover the OpenCode
  `color_scheme` dependency fanout.
- The tests in `desktopctl/src/theme/targets/qt.rs` cover the declared
  KTextEditor theme metadata and Kvantum dark/light asset selection behavior.
- The tests in `desktopctl/src/theme/targets/zsh.rs` cover the autosuggestion
  color selection across the full repo scheme catalog, including the light-only
  `fg2` fallback and the `nord` dark fallback to the main foreground when no
  muted tier clears the minimum contrast.
- `desktopctl theme list-schemes --json`, `list-presets --json`, and
  `status --json` now match the shapes consumed by Quickshell, including the
  richer scheme-preview data used by the shared card selectors.
