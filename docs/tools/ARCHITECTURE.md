# Tools Architecture

## Scope

Current map for the repo-managed tool configs under `config/`, the shell-side
tooling in `home/shell.nix`, and the matching `desktopctl` theme targets as of
2026-04-19.

## Source Of Truth

Tools with a `config/` subdirectory that the theme pipeline reads or that Home
Manager deploys.

| Tool | Repo-authored source | Live theme-owned output | Assembly | Notes |
| --- | --- | --- | --- | --- |
| Neovim | `config/nvim/**/*` | `~/.config/nvim/lua/theme-state.json`, `~/.config/nvim/lua/neovide-theme.lua` | `standalone` | Home Manager symlinks the full tree; theming writes only state files; the runtime config sanitizes `background` to `dark`/`light` and otherwise falls back silently to the installed `gruvbox` scheme |
| Alacritty | `config/alacritty/alacritty.toml` | `~/.config/alacritty/theme.toml` | `import` | Base config imports the generated fragment |
| Ghostty | `config/ghostty/config` | `~/.config/ghostty/theme.conf` | `import` | Home Manager deploys the base config at `~/.config/ghostty/config`, and that base file uses Ghostty's native `config-file` directive to load the generated fragment |
| OpenCode | `config/opencode/base.json` | `~/.config/opencode/tui.json` plus `~/.config/opencode/themes/desktopctl.json` | `concat` | Base config is schema-only; the generated concat block sets the managed global theme name, and `persist()` writes the actual OpenCode palette JSON under `themes/` |
| tmux | `config/tmux/tmux.conf` | `~/.config/tmux/colors.conf` | `import` | Base config sources the generated colors file |
| Zsh | `home/shell.nix` | `~/.config/zsh/theme-colors` | `import` | Home Manager authors the main shell init; `programs.zsh.initContent` sources the generated fragment for autosuggestion highlighting |
| Starship | `config/starship/base.toml` | `~/.config/starship.toml` | `concat` | Base prompt config plus generated palette block written at apply time |
| Zathura | `config/zathura/zathurarc` | `~/.config/zathura/colors` | `import` | Base config includes the generated colors file |
| Vicinae | `config/vicinae/settings.json` | `~/.config/vicinae/settings.theme.json` plus `~/.local/share/vicinae/themes/*.toml` | `import` | Home Manager deploys the base settings file at `~/.config/vicinae/settings.json`, that base file imports the generated fragment through Vicinae's top-level `imports` support, and the target writes theme names, per-variant `icon_theme`, font settings, and custom theme TOMLs that override or supplement Vicinae's built-ins while provider search paths remain literal |
| VS Code | `config/vscode/base.json` | `~/.config/Code/User/settings.json` | `concat` | Base JSON merged with generated theme/font block; `persist()` also syncs extension state in `state.vscdb` |
| Zed | `config/zed/base.json` | `~/.config/zed/settings.json` | `concat` | Base JSON merged with generated `theme` and font keys; the merged file is theme-owned, so Home Manager does not deploy `zed/settings.json` directly |
| Snappy Switcher | `config/snappy-switcher/base.ini` | `~/.config/snappy-switcher/config.ini` | `concat` | Base INI plus generated theme/icon/font section; daemon restarts on apply |
| Hyprland | `config/hypr/*.conf` | `~/.config/hypr/colors.conf`, `~/.config/hypr/appearance-theme.conf`, `~/.config/hypr/cursor.conf` | `standalone` | Modular repo configs deployed by Home Manager; three theme targets write standalone files into the same `~/.config/hypr/` tree |
| Quickshell | `config/quickshell/**/*` | `~/.config/quickshell/GeneratedTheme.json` | `standalone` | Home Manager symlinks the full QML tree; `Theme.qml` watches the generated JSON at runtime and falls back to built-in Gruvbox-style values before the first sync |
| Git | `config/git/ignore` | none | none | Global gitignore deployed by Home Manager; no theme integration |

Theme-only targets with no `config/` subdirectory:

| Tool | Live theme-owned output | Assembly | Notes |
| --- | --- | --- | --- |
| Bat | `~/.config/bat/config` | `standalone` | Theme selector; reads config per invocation |
| Chromium | Chromium active-profile `Preferences` web-font prefs | `command` | Patches active profiles in place by reading `Local State` and updating `webkit.webprefs.fonts` |
| Cursor | `~/.local/share/icons/default/index.theme.generated` | `standalone` | Also writes `~/.config/hypr/cursor.conf`; live-updates dconf and hyprctl |
| GTK | `~/.config/gtk-3.0/settings.ini`, `~/.config/gtk-4.0/settings.ini`, plus dconf live state | `command` | Writes GTK settings files for startup/non-GNOME consumers and sets GTK theme, color-scheme, fonts, and icon theme via dconf during runtime applies |
| GtkSourceView | `~/.local/share/libgedit-gtksourceview-300/styles/desktopctl-current.xml` and related generated style files | `standalone` | Also updates gedit's dark/light source-style dconf keys |
| OpenChamber | `~/.config/openchamber/settings.json` plus `~/.config/openchamber/themes/desktopctl.json` | `command` | Patches only OpenChamber's theme-owned settings keys and writes a generated custom theme file; the rest of `settings.json` stays app-owned |
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
- Zsh keeps its main config in `home/shell.nix`, but that Nix-authored init now
  sources the generated `~/.config/zsh/theme-colors` fragment written by the
  `zsh` theme target.
- Quickshell writes `~/.config/quickshell/GeneratedTheme.json` into the live
  config tree through `desktopctl theme sync` and later runtime applies; the
  repo no longer carries a committed generated bootstrap snapshot.
- The VS Code output path (`~/.config/Code/User/settings.json`) remains a
  non-XDG path dictated by the application.
