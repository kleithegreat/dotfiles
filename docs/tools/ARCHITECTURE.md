# Tools Architecture

## Scope

Current map for the repo-managed tool configs under `config/`, the shell-side
tooling in `home/shell.nix`, and the matching `desktopctl` theme targets as of
2026-04-03.

## Source Of Truth

Tools with a `config/` subdirectory that the theme pipeline reads or that Home
Manager deploys.

| Tool | Repo-authored source | Live theme-owned output | Assembly | Notes |
| --- | --- | --- | --- | --- |
| Neovim | `config/nvim/**/*` | `~/.config/nvim/lua/theme-state.json`, `~/.config/nvim/lua/neovide-theme.lua` | `standalone` | Home Manager symlinks the full tree; theming writes only state files |
| Alacritty | `config/alacritty/alacritty.toml` | `~/.config/alacritty/theme.toml` | `import` | Base config imports the generated fragment |
| Ghostty | `config/ghostty/base` | `~/.config/ghostty/config` | `concat` | Base file plus generated theme block written at apply time |
| tmux | `config/tmux/tmux.conf` | `~/.config/tmux/colors.conf` | `import` | Base config sources the generated colors file |
| Zsh | `home/shell.nix` | Home Manager-managed shell init | none | Shell behavior is Nix-authored; no direct theme target |
| Starship | `config/starship/base.toml` | `~/.config/starship.toml` | `concat` | Base prompt config plus generated palette block written at apply time |
| Zathura | `config/zathura/zathurarc` | `~/.config/zathura/colors` | `import` | Base config includes the generated colors file |
| Vicinae | `config/vicinae/base.json` | `~/.config/vicinae/settings.json` | `concat` | Base settings plus generated theme block written at apply time |
| VS Code | `config/vscode/base.json` | `~/.config/Code/User/settings.json` | `concat` | Base JSON merged with generated theme/font block; `persist()` also syncs extension state in `state.vscdb` |
| Snappy Switcher | `config/snappy-switcher/base.ini` | `~/.config/snappy-switcher/config.ini` | `concat` | Base INI plus generated theme/icon/font section; daemon restarts on apply |
| Hyprland | `config/hypr/*.conf` | `~/.config/hypr/colors.conf`, `~/.config/hypr/appearance-theme.conf`, `~/.config/hypr/cursor.conf` | `standalone` | Modular repo configs deployed by Home Manager; three theme targets write standalone files into the same `~/.config/hypr/` tree |
| Quickshell | `config/quickshell/**/*` | `~/.config/quickshell/GeneratedTheme.json` | `standalone` | Home Manager symlinks the full QML tree; `Theme.qml` watches the generated JSON at runtime |
| Git | `config/git/ignore` | none | none | Global gitignore deployed by Home Manager; no theme integration |

Theme-only targets with no `config/` subdirectory:

| Tool | Live theme-owned output | Assembly | Notes |
| --- | --- | --- | --- |
| Bat | `~/.config/bat/config` | `standalone` | Theme selector; reads config per invocation |
| Cursor | `~/.local/share/icons/default/index.theme.generated` | `standalone` | Also writes `~/.config/hypr/cursor.conf`; live-updates dconf and hyprctl |
| GTK | dconf live state only | `command` | Sets GTK theme, color-scheme, fonts, and icon theme via dconf |
| Qt | `~/.config/qt6ct/colors/current.conf` and others | `standalone` | Multi-file: qt6ct, qt5ct, kdeglobals, kcolorscheme, hyprqt6engine, Kvantum, Kate, KWrite |
| Spicetify | `~/.config/spicetify/Themes/ApplyTheme/color.ini` | `standalone` | Runs `spicetify update` on apply |
| Wallpaper | `awww` live state plus cached filtered wallpapers | `command` | Optional `lutgen` palette filtering; no persistent primary config file |

## Cross-Tool Relationships

- Home Manager activation guarantees that generated theme fragments exist before
  the session starts by running `desktopctl theme sync`.
- Runtime theme changes go through the same `desktopctl theme` targets with
  live reloads where the tool supports them.
- Nix owns package lifecycle for tool binaries and editor language servers;
  repo config owns runtime behavior.
- Three theme targets write generated files into `~/.config/hypr/` alongside
  Home Manager-symlinked repo configs. The repo configs source these generated
  files, so both must exist for a working session.
- Neovim and Quickshell theme targets similarly write generated state files
  into their Home Manager-symlinked config trees.
- The VS Code output path (`~/.config/Code/User/settings.json`) remains a
  non-XDG path dictated by the application.
