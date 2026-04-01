# Theming Architecture

## Scope

This document describes the current theming implementation as of April 1, 2026.
It is based on:

- `docs/theming/SPEC.md`
- `docs/theming/REVIEW.md`
- `themes/apply-theme`
- `themes/lib/schema.py`
- `themes/lib/resolve.py`
- `themes/lib/orchestrator.py`
- every file under `themes/lib/targets/`
- the current consumer integration points in `home/default.nix:225-241`,
  `home/default.nix:326-330`, `config/quickshell/Theme.qml:5-25`,
  `config/nvim/lua/plugins/colors.lua:1-14`, and
  `config/nvim/lua/config/options.lua:29-29`

## CLI Surface

`themes/apply-theme:13-37` bootstraps the repo import path from the script
location, fixes the working directories for `colors/`, `presets/`, and
`state.json`, and reflects `ThemeState` type hints into three field sets that
drive value coercion for the CLI.

The CLI supports thirteen subcommands:

- `all`, `colors`, `wallpaper`, `cursor`, `fonts`, `sync`, and `target`
- `set`, `preset`, `save-preset`, and `delete-preset`
- `list-schemes`, `list-presets`, and `status`

That full surface is implemented in `themes/apply-theme:179-427`. The rebuild-time
path is `sync`, which calls `apply_all(colors, state, runtime=False,
sync_safe=True)` instead of the runtime default path
(`themes/apply-theme:214-218`).

State mutation is split by command type:

- `cmd_set()` coerces one value, validates a full `ThemeState`, writes
  `themes/state.json`, computes the affected targets through `targets_for_key()`,
  and applies only that subset (`themes/apply-theme:228-257`).
- `cmd_preset()` loads one partial JSON patch from `themes/presets/`, merges it
  into the current state, rewrites `themes/state.json`, and then runs
  `apply_all()` (`themes/apply-theme:259-297`).
- `cmd_save_preset()` and `cmd_delete_preset()` manage the preset directory
  without applying anything immediately (`themes/apply-theme:300-339`).

The `colors` and `fonts` group commands do not use `DEPENDS` directly. They use
their own hardcoded target groups in `_BASE_COLOR_TARGETS` and `_FONT_TARGETS`,
with `_color_targets_for_state()` adding `wallpaper` only when
`filter_wallpaper` is enabled (`themes/apply-theme:141-177`, `themes/apply-theme:186-210`).

## Schema And Resolution

`themes/lib/schema.py:11-123` defines two frozen dataclasses:

- `ColorScheme`, which is a validated color family, variant, 23 named color
  fields, and one 16-entry terminal palette
- `ThemeState`, which now includes the original theme keys plus per-target mono
  font offsets for `alacritty`, `ghostty`, `gtk`, `neovide`, `qt`, and `vscode`,
  plus the `hypr_*` appearance keys consumed by `hypr_appearance`

`ThemeState.mono_font_size_for()` is the current shared helper for targets that
derive their font size from the common mono base plus a target-specific offset
(`themes/lib/schema.py:72-117`).

`themes/lib/resolve.py:31-110` is the validation layer. `load_colors()` enforces
file presence, required top-level keys, the full named-color field set, and a
16-entry hex palette. `load_state()` enforces key presence and primitive type
shape for every `ThemeState` field. `save_state()` rewrites `state.json` with
stable indentation. The resolver validates that a `variant` key exists, but it
does not constrain `variant` to a fixed dark/light enum (`themes/lib/resolve.py:31-73`).

## Target Registry

`themes/lib/targets/__init__.py:1-32` auto-discovers targets by importing every
`.py` file under `themes/lib/targets/` and registering any module that exports
`TARGET_NAME`. Duplicate names are a hard error.

The currently registered target set is:

- `alacritty`, `bat`, `cursor`, `ghostty`, `gtk`, `hypr_appearance`,
  `hyprland`, `neovide`, `neovim`, `qt`, `quickshell`, `snappy_switcher`,
  `spicetify`, `starship`, `tmux`, `vicinae`, `vscode`, and `wallpaper`

That inventory extends beyond the target list in `docs/theming/SPEC.md`,
especially with `hypr_appearance`, `neovide`, `snappy_switcher`, `spicetify`,
and `vscode`, matching the implementation drift recorded in
`docs/theming/REVIEW.md:65-76` and the live modules under `themes/lib/targets/`.

## Dependency Map And Target Selection

The dependency map is defined directly in `themes/lib/orchestrator.py:14-46`.
`targets_for_key()` is a direct lookup into that map with one special case: when
`state_key == "color_scheme"` and `state.filter_wallpaper` is false, it removes
`wallpaper` from the affected set (`themes/lib/orchestrator.py:215-220`).

The live dependency map is:

- `color_scheme` -> `alacritty`, `ghostty`, `hyprland`, `zathura`,
  `quickshell`, `neovim`, `starship`, `tmux`, `gtk`, `qt`, `vicinae`, `bat`,
  `wallpaper`, `vscode`, `spicetify`, `snappy_switcher`
- `wallpaper` and `filter_wallpaper` -> `wallpaper`
- `system_font` -> `quickshell`, `gtk`, `qt`, `vicinae`, `snappy_switcher`
- `mono_font` -> `alacritty`, `ghostty`, `gtk`, `neovide`, `quickshell`, `qt`,
  `tmux`, `vscode`
- `icon_theme` -> `gtk`, `qt`, `snappy_switcher`
- `cursor_theme` and `cursor_size` -> `cursor`
- `font_size` -> `gtk`, `qt`, `snappy_switcher`
- `mono_font_size` -> `alacritty`, `ghostty`, `gtk`, `neovide`, `qt`, `vscode`
- `alacritty_mono_font_size_offset` -> `alacritty`
- `ghostty_mono_font_size_offset` -> `ghostty`
- `gtk_mono_font_size_offset` -> `gtk`
- `neovide_mono_font_size_offset` -> `neovide`
- `qt_mono_font_size_offset` -> `qt`
- `vscode_mono_font_size_offset` -> `vscode`
- `dark_hint` -> `gtk`
- `hypr_gaps_in`, `hypr_gaps_out`, `hypr_border_size`, `hypr_rounding`,
  `hypr_blur_enabled`, `hypr_blur_size`, `hypr_blur_passes`, and
  `hypr_animations_enabled` -> `hypr_appearance`

The dependency map is therefore broader than the current prose spec in
`docs/theming/SPEC.md`, especially for `hypr_appearance`, `neovide`, `spicetify`,
`snappy_switcher`, and `vscode`, and it encodes the current `wallpaper`
special-case behavior directly in `targets_for_key()`.

## Orchestrator

`themes/lib/orchestrator.py:49-220` is the live assembly and execution engine.

`_assemble()` implements four behaviors:

- `command`: run every generated command with `subprocess.run(..., check=True,
  capture_output=True, text=True)` and aggregate failures
  (`themes/lib/orchestrator.py:57-73`)
- `import` and `standalone`: ensure the output directory exists, prepend a
  generated-file header when the target exports `COMMENT`, and write the result
  to `OUTPUT_PATH` (`themes/lib/orchestrator.py:75-82`)
- `concat`: require `BASE_PATH`, skip the target when the base file is missing,
  then either append generated text after the base file or perform a depth-1 JSON
  merge when the output suffix is `.json`
  (`themes/lib/orchestrator.py:84-105`)
- `EXTRA_OUTPUTS`: after the primary write, fan out the written content to
  additional output paths, which is how `qt` keeps `qt6ct` and `qt5ct` color
  schemes aligned (`themes/lib/orchestrator.py:110-114`)

The orchestrator's lifecycle is:

1. call `target.generate(colors, state)`
2. assemble the primary output
3. run `persist(colors, state)` if the target exports it
4. when `runtime=True`, run `RELOAD_CMD` and then `on_apply(colors, state)` as
   best-effort live-session hooks

That lifecycle is implemented by `apply_target()` and is shared by
`apply_targets()` and `apply_all()` (`themes/lib/orchestrator.py:117-220`).

Two current execution details extend the prose spec:

- `_sorted_targets()` runs file-writing targets before `command` targets so
  runtime commands see the newest generated files (`themes/lib/orchestrator.py:165-170`)
- `apply_all(..., sync_safe=True)` filters the registry through each target's
  optional `SYNC_SAFE` attribute, which is how Home Manager's activation pass
  skips runtime-only targets such as GTK and wallpaper
  (`themes/lib/orchestrator.py:191-212`)

Because `persist()` and `on_apply()` can perform their own writes and external
commands, the orchestrator no longer owns all theming-side file I/O by itself.
That behavior is visible in `cursor.py`, `qt.py`, `spicetify.py`, `vscode.py`,
and `wallpaper.py`.

## Assembly Strategies In Practice

### `import`

The live `import` targets are `alacritty`, `tmux`, and `zathura`
(`themes/lib/targets/alacritty.py:5-41`, `themes/lib/targets/tmux.py:7-23`,
`themes/lib/targets/zathura.py:5-36`). Each one writes a generated fragment while
the repo-managed base file stays deployed by Home Manager:

- `config/alacritty/alacritty.toml:1-8` imports `~/.config/alacritty/theme.toml`
- `config/tmux/tmux.conf:1-50` sources `~/.config/tmux/colors.conf`
- `config/zathura/zathurarc:1-2` includes `colors`

Only `tmux` declares an explicit reload command. `alacritty` relies on config
watching, and `zathura` has no live reload hook.

### `standalone`

The live `standalone` targets fall into two groups.

Pure single-output writers:

- `bat` writes `~/.config/bat/config` and maps known theme families and variants
  to bat's built-in theme names (`themes/lib/targets/bat.py:5-28`)
- `hyprland` writes `~/.config/hypr/colors.conf`, defining `$theme_*` variables
  and reloading Hyprland (`themes/lib/targets/hyprland.py:5-55`)
- `hypr_appearance` writes `~/.config/hypr/appearance-theme.conf` from the
  `hypr_*` state keys and reloads Hyprland
  (`themes/lib/targets/hypr_appearance.py:5-42`)
- `neovide` writes `~/.config/nvim/lua/neovide-theme.lua`
  (`themes/lib/targets/neovide.py:5-15`)
- `neovim` writes `~/.config/nvim/lua/theme-state.json`
  (`themes/lib/targets/neovim.py:7-17`)
- `quickshell` writes `~/.config/quickshell/GeneratedTheme.json`
  (`themes/lib/targets/quickshell.py:7-49`)

Standalone writers with extra side effects:

- `cursor` writes `~/.local/share/icons/default/index.theme.generated`, then in
  `persist()` updates the XCursor index symlinks plus
  `~/.config/hypr/cursor.conf`, and in `on_apply()` pushes cursor state through
  `dconf`, `hyprctl`, and the user environment
  (`themes/lib/targets/cursor.py:11-151`)
- `qt` writes the primary `qt6ct` scheme, mirrors it to `qt5ct` through
  `EXTRA_OUTPUTS`, and then writes `qt6ct.conf`, `qt5ct.conf`, `kdeglobals`,
  `current.colors`, `hyprqt6engine.conf`, the generated Kvantum theme, and Kate
  / KWrite config files in `persist()`
  (`themes/lib/targets/qt.py:11-640`)
- `spicetify` writes one generated theme under
  `~/.config/spicetify/Themes/ApplyTheme/color.ini`, ensures `user.css` exists in
  `persist()`, and runs `spicetify update` in `on_apply()`
  (`themes/lib/targets/spicetify.py:11-118`)

These standalone outputs are consumed directly by the current desktop config:

- Hyprland sources `colors.conf` and `appearance-theme.conf`
  (`config/hypr/hyprland.conf:9`, `config/hypr/appearance.conf:3`)
- Hyprlock sources `colors.conf` (`config/hypr/hyprlock.conf:1`)
- Quickshell watches `GeneratedTheme.json` (`config/quickshell/Theme.qml:10-25`)
- Neovim reads `theme-state.json` on startup
  (`config/nvim/lua/plugins/colors.lua:1-14`)
- Neovide loads `neovide-theme.lua` when `vim.g.neovide` is true
  (`config/nvim/lua/config/options.lua:29-29`)

### `concat`

The live text concat targets are `ghostty`, `starship`, and `snappy_switcher`
(`themes/lib/targets/ghostty.py:5-26`, `themes/lib/targets/starship.py:5-71`,
`themes/lib/targets/snappy_switcher.py:11-102`). Each one reads a repo-managed
base file and appends generated theme content to the final runtime config.

Two concat targets use the orchestrator's JSON merge path instead of string
concatenation:

- `vicinae` merges generated `font` and `theme` blocks into the base JSON read
  from `~/repos/dotfiles/config/vicinae/base.json`
  (`themes/lib/targets/vicinae.py:7-44`)
- `vscode` merges generated theme/font settings into the base settings JSON read
  from `~/repos/dotfiles/config/vscode/base.json`, then in `persist()` edits
  VS Code's SQLite state database to re-enable theme extensions when needed
  (`themes/lib/targets/vscode.py:10-90`)

Two concat targets also have runtime hooks:

- `snappy_switcher` restarts the daemon in `on_apply()`
  (`themes/lib/targets/snappy_switcher.py:79-102`)
- `vscode` has no reload hook, relying on VS Code's settings watcher instead
  (`themes/lib/targets/vscode.py:10-90`)

### `command`

The live `command` targets are `gtk` and `wallpaper`
(`themes/lib/targets/gtk.py:9-43`, `themes/lib/targets/wallpaper.py:14-140`).

`gtk` is command-shaped in the registry, but its current `generate()` returns no
commands. All real work happens in `on_apply()`, which writes GNOME interface
settings through `dconf` using `state.dark_hint`, `system_font`, `mono_font`,
`icon_theme`, and the target-specific GTK mono-font offset. `gtk` is marked
`SYNC_SAFE = False`, so the Home Manager activation path does not try to force it
(`themes/lib/targets/gtk.py:9-43`).

`wallpaper` has two modes:

- when `filter_wallpaper` is false, `generate()` returns a direct `swww img`
  command (`themes/lib/targets/wallpaper.py:81-85`)
- when `filter_wallpaper` is true, `generate()` returns nothing and `on_apply()`
  derives a cache key from the wallpaper file and active palette, optionally runs
  `lutgen apply --cache`, writes filtered outputs under
  `~/.cache/apply-theme/wallpaper`, and then applies either the filtered or
  original wallpaper (`themes/lib/targets/wallpaper.py:28-52`,
  `themes/lib/targets/wallpaper.py:88-140`)

`wallpaper` is also `SYNC_SAFE = False`, so rebuild-time sync writes never try to
run `swww` or `lutgen`.

## Consumer Integration

Home Manager is the current deployment layer for base config and activation:

- `home/default.nix:225-241` deploys the recursive `quickshell/` and `nvim/`
  trees, the base configs for Alacritty, tmux, and Zathura, and the packaged
  Snappy Switcher themes
- `home/default.nix:326-330` runs `themes/apply-theme sync` after the managed
  files are written

This means the theming system currently relies on two integration patterns:

- base config plus generated companion files, as used by Alacritty, tmux,
  Zathura, Hyprland, Snappy Switcher, and the JSON-merge targets
- recursively deployed config trees that coexist with generated sibling files,
  as used by Quickshell and Neovim

The shell-side and editor-side consumer entry points are currently:

- `config/quickshell/Theme.qml:5-25` for `GeneratedTheme.json`
- `config/nvim/lua/plugins/colors.lua:1-14` for `theme-state.json`
- `config/nvim/lua/config/options.lua:29-29` for `neovide-theme.lua`

## Current Contract Beyond `docs/theming/SPEC.md`

Relative to the prose spec in `docs/theming/SPEC.md`, the live implementation
surface includes additional contract points:

- extra CLI commands: `sync`, `save-preset`, and `delete-preset`
  (`themes/apply-theme:214-218`, `themes/apply-theme:300-339`)
- extra target hooks and attributes: `persist`, `on_apply`, `EXTRA_OUTPUTS`, and
  `SYNC_SAFE` (`themes/lib/orchestrator.py:110-137`,
  `themes/lib/orchestrator.py:191-212`)
- extra schema fields: `neovide_mono_font_size_offset` and the full `hypr_*`
  appearance set (`themes/lib/schema.py:91-105`)
- extra first-class targets: `hypr_appearance`, `neovide`, `snappy_switcher`,
  `spicetify`, and `vscode`
- a JSON-merge `concat` mode for `.json` outputs
  (`themes/lib/orchestrator.py:90-105`)

Those are all part of the current architecture even where the older prose spec
still describes a smaller surface.
