# Theming Architecture

## Scope

Current implementation map for the migrated Rust theming pipeline.

## Runtime Surface

| Piece | Current implementation |
| --- | --- |
| CLI entry point | `desktopctl/src/main.rs` and `desktopctl/src/theme/mod.rs` implement the full `desktopctl theme` surface. |
| Schema | `desktopctl/src/theme/schema.rs` defines `ColorScheme`, required `appearance`, centralized per-target app-theme metadata including KTextEditor theme names, `ThemeState`, canonical field ordering, compiled default theme-state values, the per-target system-font and mono-font offset contract, and the shared font-size / mono-font-size helpers. The default-state logic there still derives `dark_hint` from the default scheme's declared appearance instead of a detached constant. |
| Resolution | `desktopctl/src/theme/resolve.rs` resolves `themes/colors/`, rejects schemes that omit `appearance`, persists theme state in the shared `desktopctl.db` `theme_state` table, backfills missing required `ThemeState` keys from compiled defaults when older SQLite rows or legacy `themes/state.json` inputs are reused, canonicalizes known legacy string aliases such as older mono-font labels before validation/persistence, imports the legacy JSON on first access, and serializes canonical JSON for CLI output. |
| JSON compatibility | `desktopctl/src/theme/json.rs` preserves Python-compatible object ordering and ASCII escaping for generated JSON files and `--json` CLI output. |
| Registry | `desktopctl/src/theme/targets/mod.rs` defines target metadata, including primary generated outputs, additional hook-managed filesystem paths, and the consumed `ThemeState` key list for each target, exposes the hook surfaces, and registers all 26 current targets explicitly. |
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
| `concat` | `opencode`, `snappy_switcher`, `starship`, `vscode`, `zed` |
| `command` | `chromium`, `gtk`, `openchamber`, `wallpaper`, `where_is_my_sddm_theme` |

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
| `gtk` | `desktopctl/src/theme/targets/gtk.rs` is command-assembly but writes sync-safe GTK 3/4 `settings.ini` files from `persist()` for non-GNOME GTK consumers, then uses `on_apply()` for live dconf writes. Both the normal UI font and monospace font still route through the shared offset helpers. |
| `gtksourceview` | `desktopctl/src/theme/targets/gtksourceview.rs` writes the current GtkSourceView scheme to `desktopctl-current.xml`, mirrors the rest of the repo scheme catalog into `~/.local/share/libgedit-gtksourceview-300/styles/desktopctl-*.xml`, and updates gedit's dark/light source-style dconf keys at runtime. |
| `openchamber` | `desktopctl/src/theme/targets/openchamber.rs` is command-only and writes `~/.config/openchamber/themes/desktopctl.json` with a generated OpenChamber custom theme while patching only the theme-owned keys in `~/.config/openchamber/settings.json` (`themeId`, `themeVariant`, `useSystemTheme`, and the matching light/dark theme pointer) so the rest of the app settings remain OpenChamber-owned. |
| `opencode` | `desktopctl/src/theme/targets/opencode.rs` concatenates the repo-owned OpenCode TUI base config from `config/opencode/base.json` into `~/.config/opencode/tui.json` to select the managed `desktopctl` theme, then persists `~/.config/opencode/themes/desktopctl.json` with an ASCII-safe palette mapped onto OpenCode's upstream theme schema. |
| `qt` | `desktopctl/src/theme/targets/qt.rs` mirrors the palette into qt5ct, qt6ct, KDE, hyprqt6engine, Kvantum, Kate, and KWrite. The target writes `[Icons] Theme` into `kdeglobals`, maps the shared `Neuwaita` selection to the KDE-only `Neuwaita-KDE` wrapper icon theme from `home/gtk.nix`, drives KTextEditor from `ColorScheme.app_themes.ktexteditor`, points `hyprqt6engine` at the generated KDE `.colors` file rather than the qtct palette file so KDE's `KColorScheme` path is set, uses the shared system-font and mono-font offset helpers for `hyprqt6engine`, and still uses the centralized `ColorScheme.appearance` metadata when only dark/light asset selection is needed. The shared system baseline in `system/configuration.nix` now supplies the runtime half of that contract by enabling NixOS `qt.enable`, exporting `QT_QPA_PLATFORMTHEME=hyprqt6engine`, keeping hyprqt6engine's nonstandard plugin root visible, installing qtct/Kvantum packages system-wide without a global `QT_STYLE_OVERRIDE`, and applying the shared fontconfig tuning that gives `system_font = "SF Pro"` RGB subpixel AA plus an `SF Pro Text` preference. |
| `quickshell` | `desktopctl/src/theme/targets/quickshell.rs` writes `GeneratedTheme.json` for shell colors and fonts with Python-compatible JSON formatting, emits both mono and system font families, and derives `size`, `sizeSmall`, and `sizeLarge` from `ThemeState.font_size + quickshell_font_size_offset`. |
| `spicetify` | `desktopctl/src/theme/targets/spicetify.rs` ensures theme scaffolding exists and runs `spicetify update` on apply. |
| `vicinae` | `desktopctl/src/theme/targets/vicinae.rs` now writes only `~/.config/vicinae/settings.theme.json`, while Home Manager deploys `config/vicinae/settings.json` as the base file that imports that fragment. Its `persist()` hook still writes custom TOML themes under `~/.local/share/vicinae/themes/` using the configured Vicinae theme IDs from `ColorScheme.app_themes.vicinae`. When a scheme declares a distinct Vicinae `light_name`, the hook loads that repo scheme too so the paired light file exists alongside the active theme. |
| `vscode` | `desktopctl/src/theme/targets/vscode.rs` merges the repo base settings with theme-owned color and font keys, and now prefers a `'<mono font> Mono', '<mono font>', monospace` stack for `terminal.integrated.fontFamily` when the selected font is a Nerd Font so prompt glyphs render reliably in the integrated terminal. |
| `zed` | `desktopctl/src/theme/targets/zed.rs` concats `config/zed/base.json` with theme-owned `theme`, `buffer_font_family`, `buffer_font_size`, `ui_font_family`, and `ui_font_size` keys to produce `~/.config/zed/settings.json`. Theme names come from `ColorScheme.app_themes.zed` (falling back to `family-variant` if unset). |
| `wallpaper` | `desktopctl/src/theme/targets/wallpaper.rs` preserves the old `lutgen` cache-key behavior and `awww` runtime side effects while remaining `sync_safe = false`. |
| `where_is_my_sddm_theme` | `desktopctl/src/theme/targets/where_is_my_sddm_theme.rs` stages the currently selected wallpaper bytes at `/tmp/desktopctl-where-is-my-sddm-theme/background`, preferring the filtered wallpaper cache when that file already exists, so the root-owned bridge in `system/services.nix` can copy the image into `/var/lib/desktopctl/where-is-my-sddm-theme/background` for SDDM's static `theme.conf.user` path. |
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
| Quickshell | `config/quickshell/Theme.qml`, `config/quickshell/popups/SettingsPopup.qml`, the Fonts/Presets panes, `config/quickshell/ShellOptions.qml`, and `config/quickshell/shell.qml` call or route `desktopctl theme` through argv-safe command construction instead of hardcoded repo scripts. The settings host still stages individual `theme set` writes optimistically, serializes queued `set` / `preset` requests, and reloads or rolls back on process exit. Shell-side pane structure, shared UI primitives, the live generated `~/.config/quickshell/GeneratedTheme.json` file, and the `Theme.qml` fallback path are documented in `docs/quickshell/ARCHITECTURE.md`. |
| Neovim / Neovide | Generated `theme-state.json` and `neovide-theme.lua` are still written inside the Home Manager-symlinked `~/.config/nvim` tree. |
| OpenChamber | `desktopctl/src/theme/targets/openchamber.rs` now patches `~/.config/openchamber/settings.json` theme selection keys and persists `~/.config/openchamber/themes/desktopctl.json`, letting the desktop app keep its normal settings file while still consuming a generated desktopctl theme. |
| OpenCode | `desktopctl/src/theme/targets/opencode.rs` and `config/opencode/base.json` now generate the global `~/.config/opencode/tui.json` theme selection plus `~/.config/opencode/themes/desktopctl.json`. The target is intentionally color-only because upstream OpenCode TUI theming consumes a theme name plus theme-color JSON, and project-local OpenCode config layers can still override the global `desktopctl` theme by name. |
| Zed | `desktopctl/src/theme/targets/zed.rs` and `config/zed/base.json` together produce `~/.config/zed/settings.json`. `home/xdg.nix` does not deploy `zed/settings.json` — the merged file is owned by the theming pipeline. |
| Zsh | `home/shell.nix` sources `~/.config/zsh/theme-colors` from `programs.zsh.initContent`, while `desktopctl/src/theme/targets/zsh.rs` generates that fragment from the active `ColorScheme`. |
| Tool configs | Import or concat targets still write under `~/.config` or app-specific config paths, keeping repo-authored base files read-only. Repo-authored concat bases now resolve through `paths::repo_root()` when the target declares a relative `base_path`. |
| SDDM | `system/services.nix` points `where_is_my_sddm_theme` at the persistent root-owned `/var/lib/desktopctl/where-is-my-sddm-theme/background` file with a fixed blur radius, while the `where_is_my_sddm_theme` target stages the current wallpaper in `/tmp` and the `desktopctl-sddm-theme-sync.path` / `.service` bridge copies it into that persistent path for the greeter. |

## Validation Notes

The Rust tests cover the theming contracts that future changes are most likely
to break: schema defaults/backfill, canonical JSON formatting, target metadata,
state-key fanout, representative generated output for every target, app-theme
metadata lookup, Quickshell-facing `--json` shapes, atomic file writes, and the
`dark_hint` preservation rule for color-scheme changes.

The original migration audit compared legacy Python target output against the
Rust implementation for the migrated target set. Keep future validation focused
on stable contracts rather than mirroring that historical target-by-target log.
