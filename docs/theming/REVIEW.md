# THEMING.md Review

Reviewed on 2026-04-01.

Scope:
- Read `THEMING.md` in full.
- Read `themes/apply-theme`, every file under `themes/lib/`, every file under `themes/colors/`, and every file under `themes/presets/`.
- Cross-checked the consumer configs in `config/`, `home/default.nix`, and the current generated outputs under `~/.config` and `~/.local/share`.
- Cross-checked upstream behavior against Quickshell, Hyprland, GTK, qt6ct, and Kvantum documentation.

## Verdict

`THEMING.md` is still useful as historical context, but it is no longer an accurate current spec.

The highest-value parts are still correct at a high level:
- Alacritty, Zathura, and tmux are split with repo-managed base configs plus generated theme files.
- Hyprland color variables are generated into `~/.config/hypr/colors.conf`, and the repo configs source or consume those variables correctly.
- Quickshell is driven from `GeneratedTheme.json`.
- The Qt target really is the multi-layered qt6ct/qt5ct + KDE globals + Kvantum + hyprqt6engine chain described in the doc.

The main problem is that the implementation has moved past the documented contract:
- The schema is larger than documented.
- The target inventory is larger than documented.
- Several target contracts, output paths, and reload behaviors differ from the text.
- The data model no longer fits the doc's "`variant` is dark/light" assumption.

## What Still Matches

- `config/alacritty/alacritty.toml` imports `~/.config/alacritty/theme.toml`.
- `config/zathura/zathurarc` includes `colors`.
- `config/tmux/tmux.conf` sources `~/.config/tmux/colors.conf`.
- `config/hypr/hyprland.conf` sources `colors.conf`, and `config/hypr/appearance.conf` sources `appearance-theme.conf`.
- `config/hypr/hyprlock.conf` sources `colors.conf` and uses `$theme_*` variables.
- `config/hypr/pluginsettings.conf` uses `$theme_*` variables.
- `config/quickshell/Theme.qml` reads `GeneratedTheme.json`, and this works with the recursive Home Manager Quickshell config symlinks. The live `~/.config/quickshell/` directory currently contains both the symlinked QML files and a writable `GeneratedTheme.json`.
- All `ColorScheme` fields are consumed by at least one target. No target references a non-schema color field.

## Core Spec Drift

- The documented `ThemeState` is stale. The real schema in `themes/lib/schema.py` adds:
  - `neovide_mono_font_size_offset`
  - `hypr_gaps_in`
  - `hypr_gaps_out`
  - `hypr_border_size`
  - `hypr_rounding`
  - `hypr_blur_enabled`
  - `hypr_blur_size`
  - `hypr_blur_passes`
  - `hypr_animations_enabled`
- The documented `state.json` example is stale for the same reason.
- The documented target contract is incomplete. The implementation also uses:
  - `persist(colors, state)`
  - `on_apply(colors, state)`
  - `EXTRA_OUTPUTS`
  - `SYNC_SAFE`
- The doc says the orchestrator owns all file I/O. That is no longer true in practice:
  - `qt.py` writes multiple extra files in `persist()`.
  - `cursor.py` writes both cursor index files and `~/.config/hypr/cursor.conf`.
  - `vscode.py` edits VS Code's SQLite state DB in `persist()`.
- The CLI section is stale. The implementation also supports:
  - `sync`
  - `save-preset`
  - `delete-preset`

## Target Inventory Drift

Implemented but undocumented as first-class targets in `THEMING.md`:
- `neovide`
- `snappy_switcher`
- `spicetify`
- `vscode`

Present in the doc's directory layout or plan, but outdated as a description of the actual target set:
- `hypr_appearance` exists and is implemented, but the directory layout does not list it.
- The doc still reads like parts of Quickshell integration, Qt integration, and preset management are future work. They are already implemented.

## Target-Specific Drift

### Alacritty

- The doc still contains old `colors.toml` references in the target contract example and quick-reference table.
- The implementation and base config both use `~/.config/alacritty/theme.toml`.

### GTK

- The doc says `gtk.py` generates `gsettings set ...` commands and derives dark/light from `colors.variant`.
- The implementation is different:
  - `generate()` returns no commands.
  - `on_apply()` writes settings via `dconf`.
  - theme polarity comes from `state.dark_hint`, not from `colors.variant`.
  - the target is marked `SYNC_SAFE = False`, so Home Manager's activation pass intentionally skips it.

### Cursor

- The doc says `cursor.py` is a `command` target with no config files.
- The implementation is a `standalone` target plus side hooks:
  - generated file: `~/.local/share/icons/default/index.theme.generated`
  - symlink/update: `~/.local/share/icons/default/index.theme` and `~/.icons/default/index.theme`
  - generated Hyprland env file: `~/.config/hypr/cursor.conf`
  - runtime apply: `dconf`, `hyprctl keyword env`, `hyprctl setcursor`, and user environment import

### Neovim

- The doc says the reload model is "autocmd on file change".
- The implementation only reads `~/.config/nvim/lua/theme-state.json` on startup in `config/nvim/lua/plugins/colors.lua`.
- There is no implemented autocmd reload path.

### Quickshell

- The doc says "IPC / file watch" and suggests Theme.qml may "re-read on signal".
- The implementation is specifically file-watch based:
  - `FileView`
  - `watchChanges: true`
  - `onFileChanged: reload()`
  - `blockLoading: true`
- Quickshell IPC exists upstream, but the current theming path does not use `IpcHandler` for theme updates.

### Qt

- The broad architecture is accurately described.
- The implementation does more than the doc lists:
  - writes `~/.config/katerc`
  - writes `~/.config/kwriterc`
- The practical reload story is "write files now, restart apps or session components later". There is no runtime reload command in the target.

### Wallpaper

- The doc only describes a simple `swww img` command target.
- The implementation also supports:
  - `filter_wallpaper`
  - `lutgen apply`
  - cache-keyed filtered wallpaper generation under `~/.cache/apply-theme/wallpaper`

### tmux

- The doc says the orchestrator may reload either `tmux.conf` or `colors.conf`.
- The implementation explicitly reloads `~/.config/tmux/colors.conf` directly.

### VS Code / Snappy Switcher / Spicetify / Neovide

- These targets exist and are active in the implementation, but `THEMING.md` does not give them proper target sections.
- The Quickshell settings UI also exposes `vscode_mono_font_size_offset`, but the schema/registry sections in the doc do not treat VS Code as a first-class target.

## Consumer Config Drift

- `config/nvim/lua/config/options.lua` loads generated `neovide-theme.lua`, but the doc does not document a Neovide target at all.
- `home/default.nix` runs `themes/apply-theme sync` in activation, not `apply-theme all`.
- `home/default.nix` does not symlink `vicinae/base.json` into `~/.config`; the target reads the repo copy directly from `~/repos/dotfiles/config/vicinae/base.json`.
- The repo still contains legacy/generated-looking snapshots that the live theming system does not use as target outputs:
  - `config/ghostty/config`
  - `config/starship/starship.toml`
  - `config/vicinae/settings.json`

These files do not match the current target output locations, so keeping them in-repo is misleading even if Home Manager no longer deploys them.

## Data Model Drift

The largest schema problem is that the doc still treats `ColorScheme.variant` as binary dark/light, but the real color JSON set no longer does.

Current non-binary variants in `themes/colors/`:
- `mocha`
- `frappe`
- `macchiato`
- `latte`
- `night`
- `dawn`

This matters because several targets still branch on `colors.variant == "dark"` or write the raw variant through:
- `neovim.py` writes `"background": colors.variant`, which becomes invalid values like `"mocha"` or `"night"`.
- `qt.py` chooses dark/light Kvantum and KTextEditor branches only when the variant is literally `"dark"`.
- Some theme-name maps use family names that no longer match the JSON data:
  - JSON uses `rosepine`, but some targets map `rose-pine`
  - JSON uses `tokyonight`, but some targets map `tokyo-night`

Concrete consequences in the current implementation:
- `rose-pine` and `tokyo-night` fall back to synthesized names in `vicinae.py` and `vscode.py`.
- Catppuccin dark variants (`mocha`, `frappe`, `macchiato`) are treated as light by the current Qt dark/light branch.

`THEMING.md` does not describe this drift, so its variant-related guidance is no longer safe to treat as authoritative.

## Dependency Map Drift

The documented dependency table is not consistent with the actual target code:
- `hyprland.py` consumes `state.system_font` and `state.font_size`, but the doc's dependency map does not include `hyprland` for either key.
- `tmux.py` does not consume `mono_font`, but the doc's dependency map still lists tmux under `mono_font`.
- `neovide_mono_font_size_offset` and all `hypr_*` state keys are absent because the documented schema predates them.

## External Doc Check

These upstream docs support the current implementation more strongly than the older text in `THEMING.md`:

- Quickshell `FileView` explicitly supports `watchChanges: true` with `onFileChanged: reload()` and documents `blockLoading` for configuration files:
  - <https://quickshell.outfoxxed.me/docs/types/Quickshell.Io/FileView/>
- Quickshell `IpcHandler` exists, but it is a separate optional pattern, not what the current theming path uses:
  - <https://quickshell.outfoxxed.me/docs/types/Quickshell.Io/IpcHandler/>
- Hyprland documents both manual `hyprctl reload` and linear parsing of `source`d files, which matches the current `colors.conf` / `appearance-theme.conf` strategy:
  - <https://wiki.hypr.land/0.41.2/Configuring/Configuring-Hyprland/>
  - <https://wiki.hypr.land/0.42.0/Configuring/Keywords/>
- GTK documents:
  - `gtk-font-name` as a single string carrying family and size
  - `gtk-interface-color-scheme` as the system-wide color-scheme property
  - `gtk-application-prefer-dark-theme` as deprecated since GTK 4.20
  - <https://docs.gtk.org/gtk4/property.Settings.gtk-font-name.html>
  - <https://docs.gtk.org/gtk4/property.Settings.gtk-interface-color-scheme.html>
  - <https://docs.gtk.org/gtk4/enum.InterfaceColorScheme.html>
  - <https://docs.gtk.org/gtk4/property.Settings.gtk-application-prefer-dark-theme.html>
- qt6ct documents the expected config paths and the `QT_QPA_PLATFORMTHEME=qt6ct` model:
  - <https://github.com/trialuser02/qt6ct>
- Kvantum documents the recommended "Qt config utility + `QT_STYLE_OVERRIDE=kvantum`" chain and notes that logout/restart is the easiest recognition path:
  - <https://github.com/tsujan/Kvantum/blob/master/Kvantum/INSTALL.md>

## Bottom Line

`THEMING.md` should not be treated as the source of truth for new theming work without a cleanup pass.

The minimum update set is:
- refresh the documented schema
- document the real target contract (`persist`, `on_apply`, `EXTRA_OUTPUTS`, `SYNC_SAFE`)
- update the target inventory
- remove old `colors.toml` references
- rewrite the variant model so it no longer assumes strict dark/light strings
- update the dependency table to match real consumers
