# Theming Specification

This spec defines the theme contract for the repo: one mutable theme state,
bounded write surfaces, and consumer integrations that never overwrite
non-theming config. It is the intent document; see
`docs/theming/ARCHITECTURE.md` for the current implementation map.

## Goals

- Apply colors, fonts, wallpaper, icons, cursors, and Hyprland appearance
  without `nixos-rebuild` or manual per-app edits.
- Keep non-theming behavior in repo-authored base config.
- Support both runtime application and rebuild-time synchronization from the
  same source data.

Non-goals:

- Hand-maintaining generated outputs in the repo
- Letting consumer configs mutate theme state directly
- Giving each app a custom file-ownership model when one of the standard
  assembly strategies is sufficient

The only current exception to the "no generated outputs in the repo" rule is
`config/quickshell/GeneratedTheme.json`, which is committed as a bootstrap
snapshot because Home Manager deploys the full Quickshell tree recursively and
the live file is then overwritten by the `quickshell` target.

## Source Of Truth

| Artifact | Role | Ownership |
| --- | --- | --- |
| `themes/colors/*.json` | Palette catalog plus per-scheme metadata such as `appearance` and app theme names / IDs | Version-controlled |
| `$XDG_DATA_HOME/desktopctl/desktopctl.db` `theme_state` table | Current live selection | Mutable runtime state |
| `themes/presets/*.json` | Partial state patches | Version-controlled |
| `desktopctl/src/theme/schema.rs` | Data contract for colors and state | Authoritative schema |
| `desktopctl/src/theme/targets/*.rs` | Per-consumer theme adapters | Authoritative target registry |

Constraints:

- Targets consume resolved `ColorScheme` and `ThemeState`; they do not invent
  alternate state stores.
- Presets are partial patches, not separate full-state documents.
- Presets or direct state writes that change `color_scheme` without explicitly
  setting `dark_hint` must normalize `dark_hint` to the selected scheme's
  `appearance` before validation and apply.
- `dark_hint` remains part of `ThemeState`, but another domain may own the live
  policy for that key as long as persistence still flows through the theming
  pipeline.
- Variant strings are not guaranteed to be binary `dark`/`light`; `appearance`
  is the canonical scheme-side polarity classification for targets that need
  dark/light behavior.
- App-specific theme names and extension identifiers belong in scheme data, not
  in target-local match arms.
- Fresh installs seed `theme_state` from compiled defaults.
- Persisted `theme_state` rows or a leftover `themes/state.json` migration input
  that predate newly added required keys must backfill those keys from compiled
  defaults before validation and reuse.

## Ownership Boundaries

| Concern | Owner |
| --- | --- |
| Base application behavior | Repo-managed config under `config/` |
| Package installation and session wiring | Nix / Home Manager |
| Generated theme outputs and runtime side effects | The theming pipeline |
| Reading theme outputs | Consumer apps or shell/editor glue |

Invariants:

- Generated outputs must contain only theming or theme-adjacent runtime data.
- Base config may import generated fragments, but generated fragments must never
  become the home of unrelated behavior.
- Consumers may read generated files, but they do not define the schema or edit
  outputs directly.
- File-writing targets and preset JSON saves must replace outputs atomically so
  live consumers do not observe truncated writes.
- State mutations that require target application must only persist the new
  theme state after the required target apply succeeds.
- Persisting `dark_hint` belongs to the theming pipeline, even when another
  runtime controller decides the current desired value.

## Assembly Model

| Strategy | Use when | Write boundary |
| --- | --- | --- |
| `import` | App supports includes/imports | Only the generated fragment is writable |
| `standalone` | The output file is purely theming by nature | The whole file is theme-owned |
| `concat` | The app needs base content plus generated theme content | Base file is read-only; final output is writable |
| `command` | No standalone generated file is needed, or the target must patch live runtime settings in place | The pipeline owns only the documented side effect or targeted preference patch |

Constraints:

- Every target declares exactly one assembly strategy.
- `base_path` inputs are read-only to the orchestrator.
- `concat` target `base_path` may be absolute, `~/...`, or repo-relative; a
  repo-relative path is resolved from `paths::repo_root()`.
- JSON `concat` targets must preserve base data and overlay only theme-managed
  keys.
- Missing `base_path` inputs are hard failures; the orchestrator must not treat
  them as silent skips.
- Rebuild-time sync may skip runtime-only targets.

## Target Contract

Required surface:

| Attribute / hook | Purpose |
| --- | --- |
| `TargetMetadata.name` | Stable CLI and registry identifier |
| `TargetMetadata.assembly` | Write strategy |
| `generate(colors, state)` | Produce theme content or commands for the target |
| `TargetMetadata.output_path` | Required for file-writing targets |
| `TargetMetadata.base_path` | Required for `concat` targets |

Optional surface:

| Attribute / hook | Purpose |
| --- | --- |
| `TargetMetadata.reload_cmd` | Best-effort live reload after writes |
| `TargetMetadata.comment` | Generated-file header prefix |
| `TargetMetadata.extra_outputs` | Mirror one generated output to additional paths |
| `TargetMetadata.sync_safe` | Allow or forbid rebuild-time `sync` application |
| `persist(colors, state)` | Required post-write persistence work |
| `on_apply(colors, state)` | Runtime-only follow-up actions |

Constraints:

- `generate()` is the declared output boundary for the target.
- Extra hooks must stay within the target's documented ownership boundary.
- Runtime hooks may fail without invalidating successful file generation, but
  missing generated files are hard failures.

## Data Contract

`ColorScheme` represents the resolved palette and scheme metadata:

| Group | Required fields |
| --- | --- |
| Identity | `family`, `variant`, `appearance` |
| App metadata | `app_themes` entries for targets that need app-specific theme names or identifiers |
| Backgrounds | `bg`, `bg_dim`, `bg1`, `bg2`, `bg3` |
| Foregrounds | `fg`, `fg2`, `fg3`, `fg4` |
| Semantic colors | `red`, `green`, `yellow`, `blue`, `purple`, `cyan`, `orange`, `accent` |
| Bright colors | `red_bright`, `green_bright`, `yellow_bright`, `blue_bright`, `purple_bright`, `cyan_bright`, `orange_bright` |
| Terminal palette | `palette` with exactly 16 entries |

`ThemeState` groups runtime selections:

| Group | Keys |
| --- | --- |
| Palette and assets | `color_scheme`, `wallpaper`, `filter_wallpaper`, `icon_theme`, `cursor_theme`, `cursor_size`, `dark_hint` |
| Fonts | `system_font`, `mono_font`, `font_size`, `mono_font_size` |
| Per-target font offsets | `quickshell_font_size_offset`, `gtk_font_size_offset`, `qt_font_size_offset` |
| Legacy tolerated state | `chromium_font_size_offset` |
| Per-target mono offsets | `alacritty_*`, `ghostty_*`, `gtk_*`, `neovide_*`, `qt_*`, `vscode_*` mono-font offset keys |
| Hyprland appearance | `hypr_gaps_in`, `hypr_gaps_out`, `hypr_border_size`, `hypr_rounding`, `hypr_blur_enabled`, `hypr_blur_size`, `hypr_blur_passes`, `hypr_animations_enabled` |

Constraints:

- Color JSON must satisfy the full `ColorScheme` field set, including explicit
  `appearance`, and a 16-entry palette.
- `ThemeState` is the only mutable theme selection schema.
- `chromium_font_size_offset` remains in persisted state for backward
  compatibility, but current targets ignore it and Chromium page sizes stay at
  Chromium-managed defaults.
- Persisted `theme_state` rows and legacy `themes/state.json` imports that are
  missing newly added required keys must be normalized with compiled defaults
  before validation, target apply, and any rewrite back to SQLite.
- `color_scheme` mutations may also rewrite `dark_hint` during normalization;
  callers that need a different hint must set `dark_hint` explicitly.
- Theme-state storage is row-oriented (`key` + JSON-encoded `value`), but
  `desktopctl theme status --json` must preserve the canonical field order from
  `THEME_STATE_FIELD_ORDER`.
- Targets that need dark/light behavior must use `ColorScheme.appearance`,
  documented state, or another documented normalization rule; they must not
  assume variant strings are binary.
- Targets that need app-specific theme names or extension identifiers must read
  them from `ColorScheme.app_themes`, not duplicate family/variant lookup
  tables in target code.

## Target Inventory

| Target | Assembly | Theme-owned output or side effect |
| --- | --- | --- |
| `alacritty` | `import` | `~/.config/alacritty/theme.toml` |
| `bat` | `standalone` | `~/.config/bat/config` |
| `chromium` | `command` | Chromium active-profile `Preferences` web-font preferences |
| `cursor` | `standalone` | Cursor indexes, Hyprland cursor env, runtime cursor apply |
| `ghostty` | `concat` | `~/.config/ghostty/config` |
| `gtk` | `command` | GTK interface settings |
| `gtksourceview` | `standalone` | GtkSourceView style files under `~/.local/share/libgedit-gtksourceview-300/styles/` plus gedit source-style dconf keys |
| `hypr_appearance` | `standalone` | `~/.config/hypr/appearance-theme.conf` |
| `hyprland` | `standalone` | `~/.config/hypr/colors.conf` |
| `neovide` | `standalone` | `~/.config/nvim/lua/neovide-theme.lua` |
| `neovim` | `standalone` | `~/.config/nvim/lua/theme-state.json` |
| `opencode` | `concat` | `~/.config/opencode/tui.json` plus `~/.config/opencode/themes/desktopctl.json` |
| `qt` | `standalone` | qtct, KDE, Kvantum, and editor theme files |
| `quickshell` | `standalone` | `~/.config/quickshell/GeneratedTheme.json` |
| `snappy_switcher` | `concat` | `~/.config/snappy-switcher/config.ini` |
| `spicetify` | `standalone` | Generated Spicetify theme files plus runtime apply |
| `starship` | `concat` | `~/.config/starship.toml` |
| `tmux` | `import` | `~/.config/tmux/colors.conf` |
| `vicinae` | `concat` | `~/.config/vicinae/settings.json` |
| `vscode` | `concat` | `~/.config/Code/User/settings.json` plus state DB adjustments |
| `wallpaper` | `command` | `awww` apply and optional filtered wallpaper cache |
| `zathura` | `import` | `~/.config/zathura/colors` |

## Target Selection

State changes fan out by ownership, not by CLI convenience.

| State key(s) | Affected targets |
| --- | --- |
| `color_scheme` | `alacritty`, `bat`, `ghostty`, `gtk`, `gtksourceview`, `hyprland`, `neovim`, `opencode`, `qt`, `quickshell`, `snappy_switcher`, `spicetify`, `starship`, `tmux`, `vicinae`, `vscode`, `wallpaper`\*, `zathura` |
| `wallpaper`, `filter_wallpaper` | `wallpaper` |
| `system_font` | `chromium`, `gtk`, `qt`, `quickshell`, `snappy_switcher`, `vicinae` |
| `mono_font` | `alacritty`, `chromium`, `ghostty`, `gtk`, `neovide`, `qt`, `quickshell`, `tmux`, `vscode` |
| `icon_theme` | `gtk`, `qt`, `snappy_switcher` |
| `font_size` | `gtk`, `qt`, `quickshell`, `snappy_switcher` |
| `quickshell_font_size_offset` | `quickshell` |
| `gtk_font_size_offset` | `gtk` |
| `qt_font_size_offset` | `qt` |
| `chromium_font_size_offset` | none (legacy tolerated state key) |
| `mono_font_size` | `alacritty`, `ghostty`, `gtk`, `neovide`, `qt`, `vscode` |
| Per-target `*_mono_font_size_offset` | The named target only |
| `dark_hint` | `gtk` |
| `cursor_theme`, `cursor_size` | `cursor` |
| Hyprland appearance keys | `hypr_appearance` |

\* `wallpaper` is dropped from `color_scheme` when `filter_wallpaper` is false.

The dependency map in code must remain a direct encoding of this table.

## Home Manager And Consumer Integration

| Integration point | Contract |
| --- | --- |
| `xdg.configFile` | May deploy base config and static trees, not mutable generated outputs |
| Recursive trees | Allowed when generated sibling files remain writable, as with `quickshell/` and `nvim/` |
| Activation hook | Rebuild-time sync writes only outputs safe to materialize during activation |
| Quickshell | Reads `GeneratedTheme.json`; `system_font` and `font_size` define the shell UI baseline, `quickshell_font_size_offset` can refine the shell target without changing GTK/Qt/snappy-switcher, and `mono_font` remains for monospaced or glyph-oriented surfaces; see `docs/quickshell/SPEC.md` for shell-side constraints |
| Chromium | Reads the active profile `Preferences` web-font prefs patched by the `chromium` target; the target uses `Local State` `profile.last_active_profiles` when present and falls back to `Default`, manages web font families only, clears any previously managed page-size prefs so Chromium falls back to its own defaults, and leaves browser chrome following GTK/Qt integration outside that prefs surface |
| Gedit / GtkSourceView | Reads generated styles from `~/.local/share/libgedit-gtksourceview-300/styles/`; gedit's light/dark source-style selection is theme-owned |
| Hyprland | Reads `colors.conf` and `appearance-theme.conf` |
| Neovim / Neovide | Read generated theme state files rather than embedding palette logic in Home Manager |
| OpenCode | Reads the generated global `tui.json` theme selection and the generated `themes/desktopctl.json` palette under `~/.config/opencode/`; the target is intentionally color-only because upstream TUI theming exposes a `theme` selector plus theme-color JSON keys, while later project-local OpenCode config layers can still override the global theme by upstream precedence |

Constraint:

- `config/quickshell/GeneratedTheme.json` is the only committed generated
  snapshot currently allowed in the repo. Additional committed generated
  outputs are still forbidden.

## Qt / KDE Constraint

Qt theming is intentionally multi-layered because a plain Qt palette is not
enough for KDE and Kirigami apps on Hyprland. See `docs/theming/QUIRKS.md` for
the rationale and current limitations.
