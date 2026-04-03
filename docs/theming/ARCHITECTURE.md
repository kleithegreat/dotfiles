# Theming Architecture

## Scope

Current implementation map for `themes/apply-theme`, `themes/lib/`, and the
consumer entry points as of 2026-04-02.

## Runtime Surface

| Piece | Current implementation |
| --- | --- |
| CLI | `themes/apply-theme` bootstraps repo paths, coerces CLI values, loads colors/state, and dispatches to the orchestrator |
| Schema | `themes/lib/schema.py` defines `ColorScheme`, `ThemeState`, and the shared mono-font-offset helpers |
| Resolution | `themes/lib/resolve.py` validates color JSON, validates `state.json`, and persists state updates |
| Registry | `themes/lib/targets/__init__.py` auto-discovers target modules by `TARGET_NAME` |
| Orchestrator | `themes/lib/orchestrator.py` handles dependency selection, assembly, post-write hooks, reload hooks, and `SYNC_SAFE` filtering |

## CLI Surface

| Command group | Commands | Current behavior |
| --- | --- | --- |
| Apply scopes | `all`, `colors`, `fonts`, `wallpaper`, `cursor`, `sync`, `target` | `sync` disables runtime hooks and filters to `SYNC_SAFE` targets |
| State mutation | `set`, `preset`, `save-preset`, `delete-preset` | `set` rewrites one key and applies affected targets only; `preset` merges a partial patch into state |
| Inspection | `list-schemes`, `list-presets`, `status` | No writes |

## Registered Targets

| Assembly | Targets |
| --- | --- |
| `import` | `alacritty`, `tmux`, `zathura` |
| `standalone` | `bat`, `cursor`, `hypr_appearance`, `hyprland`, `neovide`, `neovim`, `qt`, `quickshell`, `spicetify` |
| `concat` | `ghostty`, `snappy_switcher`, `starship`, `vicinae`, `vscode` |
| `command` | `gtk`, `wallpaper` |

Targets with notable extra behavior:

| Target | Extra behavior beyond a single generated file |
| --- | --- |
| `cursor` | Persists cursor index files and Hyprland cursor env, then pushes runtime cursor state |
| `gtk` | Performs all real work in `on_apply()` via dconf and is `SYNC_SAFE = False` |
| `qt` | Mirrors the palette to Qt5, writes qtct/KDE/Kvantum/Kate/KWrite files in `persist()`, and has no live reload hook |
| `spicetify` | Ensures theme scaffolding exists, then runs `spicetify update` at apply time |
| `vscode` | JSON-merges settings and adjusts VS Code's SQLite state DB in `persist()` |
| `wallpaper` | Optionally builds cached filtered wallpapers and is `SYNC_SAFE = False` |

## Assembly And Selection

| Concern | Current implementation |
| --- | --- |
| File writes | `import` and `standalone` write one output; `concat` reads `BASE_PATH` and either appends text or depth-1 merges JSON |
| Generated headers | Added for non-JSON targets when a target exports `COMMENT` |
| Extra outputs | `EXTRA_OUTPUTS` mirrors the already-written primary output to additional paths |
| Post-write hooks | `persist()` runs before runtime reloads and must succeed |
| Runtime hooks | `RELOAD_CMD` and `on_apply()` run only when `runtime=True` |
| Target ordering | Command targets run after file-writing targets so side effects see fresh files |
| `color_scheme` special case | `targets_for_key()` drops `wallpaper` when `filter_wallpaper` is false |

## Consumer Integration

| Consumer | Current integration |
| --- | --- |
| Home Manager | Deploys base config and runs `themes/apply-theme sync` after managed files are written |
| Hyprland | Reads generated `colors.conf` and `appearance-theme.conf` |
| Quickshell | Watches generated `GeneratedTheme.json` |
| Neovim / Neovide | Read generated `theme-state.json` and `neovide-theme.lua` |
| Tool configs | Import or concatenate generated fragments under `~/.config` |

The Qt stack is intentionally multi-layered because KDE/Kirigami consumers need
more than a plain palette. See `docs/theming/QUIRKS.md`.
