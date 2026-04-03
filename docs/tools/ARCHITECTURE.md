# Tools Architecture

## Scope

Current map for the repo-managed tool configs under `config/`, the shell-side
tooling in `home/shell.nix`, and the matching theme targets as of 2026-04-02.

## Source Of Truth

| Tool | Repo-authored source | Live theme-owned output | Assembly | Notes |
| --- | --- | --- | --- | --- |
| Neovim | `config/nvim/**/*` | `~/.config/nvim/lua/theme-state.json`, `~/.config/nvim/lua/neovide-theme.lua` | `standalone` | Home Manager symlinks the full tree; theming writes only state files |
| Alacritty | `config/alacritty/alacritty.toml` | `~/.config/alacritty/theme.toml` | `import` | Base config imports the generated fragment |
| Ghostty | `config/ghostty/base` | `~/.config/ghostty/config` | `concat` | The committed `config/ghostty/config` is a snapshot, not the active base |
| tmux | `config/tmux/tmux.conf` | `~/.config/tmux/colors.conf` | `import` | Base config sources the generated colors file |
| Zsh | `home/shell.nix` | Home Manager-managed shell init | none | Shell behavior is Nix-authored; no direct theme target |
| Starship | `config/starship/base.toml` | `~/.config/starship.toml` | `concat` | Home Manager enables Starship; theming appends the palette block |
| Zathura | `config/zathura/zathurarc` | `~/.config/zathura/colors` | `import` | Base config includes the generated colors file |
| Vicinae | `config/vicinae/base.json` | `~/.config/vicinae/settings.json` | `concat` | Shallow JSON merge; committed snapshots are not the active inputs |

## Tool Map

| Tool | Structure | Theme integration | Notable coupling |
| --- | --- | --- | --- |
| Neovim | `init.lua`, `lua/config/`, `lua/plugins/`, `after/ftplugin/`, locked plugins in `lazy-lock.json` | Reads generated theme state on startup; Neovide reads a generated Lua file | LSP servers come from Nix; `vimtex` is tied to Zathura and TeX Live |
| Alacritty | Small stable TOML plus imported theme fragment | Generated font and palette fragment | Shares the repo's mono-font theme model |
| Ghostty | Thin repo base plus generated final config | Generated font/color block appended to the base | Parallel terminal role with Alacritty |
| tmux | Stable behavioral config plus sourced colors file | Generated statusline and border colors | Explicit truecolor tuning for Alacritty and Ghostty |
| Zsh | Entire shell config expressed through Home Manager | No direct theme target; prompt comes from Starship | Enables Starship, zoxide, fzf, eza, bat, and shell helpers |
| Starship | Stable prompt layout in `base.toml` | Generated palette block with contrast-aware foregrounds | Rendered through Zsh integration and assumes Nerd Font-capable terminals |
| Zathura | Minimal base file plus included colors file | Generated UI/recolor settings | Used as VimTeX's PDF viewer |
| Vicinae | Small base JSON plus generated merged settings | Generated font family and theme name mapping | Provider paths are tuned for Nix/XDG application locations |

## Cross-Tool Relationships

- Home Manager activation guarantees that generated theme fragments exist before
  the session starts.
- Runtime theme changes go through the same `themes/apply-theme` targets with
  live reloads where the tool supports them.
- Nix owns package lifecycle for tool binaries and editor language servers;
  repo config owns runtime behavior.
