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

## Source Of Truth

| Artifact | Role | Ownership |
| --- | --- | --- |
| `themes/colors/*.json` | Palette catalog | Version-controlled |
| `themes/state.json` | Current live selection | Mutable runtime state |
| `themes/presets/*.json` | Partial state patches | Version-controlled |
| `desktopctl/src/theme/schema.rs` | Data contract for colors and state | Authoritative schema |
| `desktopctl/src/theme/targets/*.rs` | Per-consumer theme adapters | Authoritative target registry |

Constraints:

- Targets consume resolved `ColorScheme` and `ThemeState`; they do not invent
  alternate state stores.
- Presets are partial patches, not separate full-state documents.
- Variant strings are not guaranteed to be binary `dark`/`light`; targets that
  need polarity must normalize it explicitly.

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

## Assembly Model

| Strategy | Use when | Write boundary |
| --- | --- | --- |
| `import` | App supports includes/imports | Only the generated fragment is writable |
| `standalone` | The output file is purely theming by nature | The whole file is theme-owned |
| `concat` | The app needs base content plus generated theme content | Base file is read-only; final output is writable |
| `command` | No file is needed | The pipeline owns only the invoked side effect |

Constraints:

- Every target declares exactly one assembly strategy.
- `base_path` inputs are read-only to the orchestrator.
- JSON `concat` targets must preserve base data and overlay only theme-managed
  keys.
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

`ColorScheme` represents the resolved palette:

| Group | Required fields |
| --- | --- |
| Identity | `family`, `variant` |
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
| Per-target mono offsets | `alacritty_*`, `ghostty_*`, `gtk_*`, `neovide_*`, `qt_*`, `vscode_*` mono-font offset keys |
| Hyprland appearance | `hypr_gaps_in`, `hypr_gaps_out`, `hypr_border_size`, `hypr_rounding`, `hypr_blur_enabled`, `hypr_blur_size`, `hypr_blur_passes`, `hypr_animations_enabled` |

Constraints:

- Color JSON must satisfy the full `ColorScheme` field set and a 16-entry
  palette.
- `ThemeState` is the only mutable theme selection schema.
- Targets that need dark/light behavior must derive it from documented state or
  a normalization rule, not from an undocumented assumption about variant
  strings.

## Target Inventory

| Target | Assembly | Theme-owned output or side effect |
| --- | --- | --- |
| `alacritty` | `import` | `~/.config/alacritty/theme.toml` |
| `bat` | `standalone` | `~/.config/bat/config` |
| `cursor` | `standalone` | Cursor indexes, Hyprland cursor env, runtime cursor apply |
| `ghostty` | `concat` | `~/.config/ghostty/config` |
| `gtk` | `command` | GTK interface settings |
| `hypr_appearance` | `standalone` | `~/.config/hypr/appearance-theme.conf` |
| `hyprland` | `standalone` | `~/.config/hypr/colors.conf` |
| `neovide` | `standalone` | `~/.config/nvim/lua/neovide-theme.lua` |
| `neovim` | `standalone` | `~/.config/nvim/lua/theme-state.json` |
| `qt` | `standalone` | qtct, KDE, Kvantum, and editor theme files |
| `quickshell` | `standalone` | `~/.config/quickshell/GeneratedTheme.json` |
| `snappy_switcher` | `concat` | `~/.config/snappy-switcher/config.ini` |
| `spicetify` | `standalone` | Generated Spicetify theme files plus runtime apply |
| `starship` | `concat` | `~/.config/starship.toml` |
| `tmux` | `import` | `~/.config/tmux/colors.conf` |
| `vicinae` | `concat` | `~/.config/vicinae/settings.json` |
| `vscode` | `concat` | `~/.config/Code/User/settings.json` plus state DB adjustments |
| `wallpaper` | `command` | `swww` apply and optional filtered wallpaper cache |
| `zathura` | `import` | `~/.config/zathura/colors` |

## Target Selection

State changes fan out by ownership, not by CLI convenience.

| State key(s) | Affected targets |
| --- | --- |
| `color_scheme` | `alacritty`, `bat`, `ghostty`, `gtk`, `hyprland`, `neovim`, `qt`, `quickshell`, `snappy_switcher`, `spicetify`, `starship`, `tmux`, `vicinae`, `vscode`, `wallpaper`\*, `zathura` |
| `wallpaper`, `filter_wallpaper` | `wallpaper` |
| `system_font` | `gtk`, `qt`, `quickshell`, `snappy_switcher`, `vicinae` |
| `mono_font` | `alacritty`, `ghostty`, `gtk`, `neovide`, `qt`, `quickshell`, `tmux`, `vscode` |
| `icon_theme` | `gtk`, `qt`, `snappy_switcher` |
| `font_size` | `gtk`, `qt`, `snappy_switcher` |
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
| Quickshell | Reads `GeneratedTheme.json`; see `docs/quickshell/SPEC.md` for shell-side constraints |
| Hyprland | Reads `colors.conf` and `appearance-theme.conf` |
| Neovim / Neovide | Read generated theme state files rather than embedding palette logic in Home Manager |

## Qt / KDE Constraint

Qt theming is intentionally multi-layered because a plain Qt palette is not
enough for KDE and Kirigami apps on Hyprland. See `docs/theming/QUIRKS.md` for
the rationale and current limitations.
