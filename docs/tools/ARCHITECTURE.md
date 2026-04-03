# Tools Architecture

## Scope

Current map for the repo-managed tool configs under `config/`, the shell-side
tooling in `home/shell.nix`, and the matching theme targets as of 2026-04-02.

## Source Of Truth

Tools with a `config/` subdirectory that the theme pipeline reads or that Home
Manager deploys.

| Tool | Repo-authored source | Live theme-owned output | Assembly | Notes |
| --- | --- | --- | --- | --- |
| Neovim | `config/nvim/**/*` | `~/.config/nvim/lua/theme-state.json`, `~/.config/nvim/lua/neovide-theme.lua` | `standalone` | Home Manager symlinks the full tree; theming writes only state files |
| Alacritty | `config/alacritty/alacritty.toml` | `~/.config/alacritty/theme.toml` | `import` | Base config imports the generated fragment |
| Ghostty | `config/ghostty/base` | `~/.config/ghostty/config` | `concat` | The committed `config/ghostty/config` is a **stale snapshot**, not the active base |
| tmux | `config/tmux/tmux.conf` | `~/.config/tmux/colors.conf` | `import` | Base config sources the generated colors file |
| Zsh | `home/shell.nix` | Home Manager-managed shell init | none | Shell behavior is Nix-authored; no direct theme target |
| Starship | `config/starship/base.toml` | `~/.config/starship.toml` | `concat` | The committed `config/starship/starship.toml` is a **stale snapshot** of pipeline output |
| Zathura | `config/zathura/zathurarc` | `~/.config/zathura/colors` | `import` | Base config includes the generated colors file |
| Vicinae | `config/vicinae/base.json` | `~/.config/vicinae/settings.json` | `concat` | The committed `config/vicinae/settings.json` is a **stale snapshot** of pipeline output; `config/vicinae/vicinae.json` is an **inert snapshot** of older UI preferences, unused by any pipeline or deployment |
| VS Code | `config/vscode/base.json` | `~/.config/Code/User/settings.json` | `concat` | Base JSON merged with generated theme/font block; `persist()` also syncs extension state in `state.vscdb` |
| Snappy Switcher | `config/snappy-switcher/base.ini` | `~/.config/snappy-switcher/config.ini` | `concat` | Base INI plus generated theme/icon/font section; daemon restarts on apply |
| Hyprland | `config/hypr/*.conf` (12 files) | `~/.config/hypr/colors.conf`, `~/.config/hypr/appearance-theme.conf`, `~/.config/hypr/cursor.conf` | `standalone` | Modular repo configs deployed by Home Manager; three theme targets write standalone files into the same `~/.config/hypr/` tree, sourced by the repo configs |
| Quickshell | `config/quickshell/**/*` (QML tree) | `~/.config/quickshell/GeneratedTheme.json` | `standalone` | Home Manager symlinks the full QML tree; `Theme.qml` watches the generated JSON at runtime |
| Git | `config/git/ignore` | none | none | Global gitignore deployed by Home Manager; no theme integration |

Theme-only targets with no `config/` subdirectory:

| Tool | Live theme-owned output | Assembly | Notes |
| --- | --- | --- | --- |
| Bat | `~/.config/bat/config` | `standalone` | Theme selector; reads config per invocation |
| Cursor | `~/.local/share/icons/default/index.theme.generated` | `standalone` | Also writes `~/.config/hypr/cursor.conf`; live-updates dconf and hyprctl |
| GTK | dconf live state only | `command` | Sets adw-gtk3 variant via dconf; no persistent file output |
| Qt | `~/.config/qt6ct/colors/current.conf` and others | `standalone` | Multi-file: qt6ct, qt5ct, kdeglobals, kcolorscheme, hyprqt6engine, kvantum |
| Spicetify | `~/.config/spicetify/Themes/ApplyTheme/color.ini` | `standalone` | Runs `spicetify update` on apply |
| Wallpaper | swww live state only | `command` | Optional lutgen palette filtering; no persistent config |

## Tool Map

| Tool | Structure | Theme integration | Notable coupling |
| --- | --- | --- | --- |
| Neovim | `init.lua`, `lua/config/`, `lua/plugins/`, `after/ftplugin/`, locked plugins in `lazy-lock.json`, spell dictionary | Reads generated theme state on startup; Neovide reads a generated Lua file | LSP servers come from Nix; `vimtex` is tied to Zathura and TeX Live |
| Alacritty | Small stable TOML plus imported theme fragment | Generated font and palette fragment | Shares the repo's mono-font theme model |
| Ghostty | Thin repo base plus generated final config | Generated font/color block appended to the base | Parallel terminal role with Alacritty |
| tmux | Stable behavioral config plus sourced colors file | Generated statusline and border colors | Explicit truecolor tuning for Alacritty and Ghostty |
| Zsh | Entire shell config expressed through Home Manager | No direct theme target; prompt comes from Starship | Enables Starship, zoxide, fzf, eza, bat, and shell helpers |
| Starship | Stable prompt layout in `base.toml` | Generated palette block with contrast-aware foregrounds | Rendered through Zsh integration and assumes Nerd Font-capable terminals |
| Zathura | Minimal base file plus included colors file | Generated UI/recolor settings | Used as VimTeX's PDF viewer |
| Vicinae | Small base JSON plus generated merged settings | Generated font family and theme name mapping | Provider paths are tuned for Nix/XDG application locations |
| VS Code | Comprehensive base JSON with editor, git, extension, and remote settings | Generated theme name, font family, and font size merged into base; extension state DB synced | Desktop entry overridden in Home Manager for Hyprland workspace tracking |
| Snappy Switcher | Small base INI with layout and icon settings | Generated theme colors, icon theme, and font section appended to base | Daemon restart required; theme file map covers all supported color schemes |
| Hyprland | Modular split: `hyprland.conf` sources 10 fragment files covering monitors, env, input, appearance, plugins, keybinds, rules, and autostart | Three standalone theme files sourced by the repo configs: `colors.conf` (color variables), `appearance-theme.conf` (gaps, rounding, blur, animations), `cursor.conf` (cursor env vars) | Plugin configs reference `$theme_*` variables from `colors.conf`; `appearance.conf` sources `appearance-theme.conf` |
| Quickshell | 65-file QML component tree: services, bar widgets, popups, settings panes, reusable components | `Theme.qml` singleton watches `GeneratedTheme.json` with hardcoded Gruvbox Dark fallbacks | Tight coupling to Hyprland via display, workspace, and window management APIs |
| Git | Single global gitignore file | None | Deployed by Home Manager as `~/.config/git/ignore` |
| Bat | No repo config; fully theme-generated | Maps (family, variant) to bat's built-in theme names | Enabled through `home/shell.nix`; `programs.bat` |
| Cursor | No repo config; standalone theme target | X/Hypr cursor theme files plus live dconf and hyprctl updates | Writes into `~/.config/hypr/` alongside Hyprland's repo configs |
| Qt | No repo config; multi-file standalone target | Colors written to qt6ct, qt5ct, kdeglobals, kcolorscheme, hyprqt6engine, kvantum | Kvantum theme asset paths are Nix-aware |
| Spicetify | No repo config; standalone theme target | Color palette with luminance-based blending | Runs `spicetify update` post-apply to patch Spotify |

## Cross-Tool Relationships

- Home Manager activation guarantees that generated theme fragments exist before
  the session starts.
- Runtime theme changes go through the same `themes/apply-theme` targets with
  live reloads where the tool supports them.
- Nix owns package lifecycle for tool binaries and editor language servers;
  repo config owns runtime behavior.
- Three theme targets write generated files into `~/.config/hypr/` alongside
  Home Manager-symlinked repo configs. The repo configs source these generated
  files, so both must exist for a working session.
- Neovim and Quickshell theme targets similarly write generated state files
  into their Home Manager-symlinked config trees.
- The VS Code output path (`~/.config/Code/User/settings.json`) is a non-XDG
  path dictated by the application, unlike the other tools.
