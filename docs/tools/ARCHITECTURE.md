# Tools Architecture

## Scope

This document covers the tool configs requested for review:

- `config/nvim/`
- `config/alacritty/`
- `config/ghostty/`
- `config/tmux/`
- `config/starship/`
- `config/zathura/`
- `config/vicinae/`
- `home/shell.nix`
- the matching `apply-theme` targets in `themes/lib/targets/`

It focuses on structure, source of truth, theme assembly, and cross-tool relationships.

## Theme Pipeline

Home Manager runs `themes/apply-theme sync` during activation (`home/default.nix`), so the generated files exist before the session starts. The runtime theme path is the same `themes/apply-theme` CLI, but in normal mode it also runs per-target reload hooks where they exist.

The core assembly logic lives in `themes/lib/orchestrator.py`. For the tools in this document it uses three patterns:

- `import`: the repo-managed config stays stable and sources a generated fragment.
- `concat`: `apply-theme` combines a repo-managed base file with generated content, or does a shallow JSON merge for JSON outputs.
- `standalone`: `apply-theme` writes a small generated state file that the tool reads directly.

That split matters because not every committed file under `config/` is actually the runtime source of truth. For Ghostty, Starship, and Vicinae, the live file is written straight into `~/.config/...` by the target, and the committed generated snapshots in this repo are secondary at best.

## Source Of Truth Summary

| Tool | Repo-authored source | Live output | Assembly | Notes |
| --- | --- | --- | --- | --- |
| Neovim | `config/nvim/**/*` | `~/.config/nvim/lua/theme-state.json` | `standalone` | Home Manager symlinks the full config tree; `apply-theme` only writes theme state |
| Alacritty | `config/alacritty/alacritty.toml` | `~/.config/alacritty/theme.toml` | `import` | Base config imports generated theme fragment |
| Ghostty | `config/ghostty/base` | `~/.config/ghostty/config` | `concat` | Base file is effectively empty today; committed `config/ghostty/config` is just a snapshot |
| tmux | `config/tmux/tmux.conf` | `~/.config/tmux/colors.conf` | `import` | Base config sources generated colors file |
| Starship | `config/starship/base.toml` | `~/.config/starship.toml` | `concat` | Base config plus generated palette block; committed `config/starship/starship.toml` is a snapshot |
| Zathura | `config/zathura/zathurarc` | `~/.config/zathura/colors` | `import` | Base config includes generated color file |
| Vicinae | `config/vicinae/base.json` | `~/.config/vicinae/settings.json` | `concat` | Shallow JSON merge; committed `config/vicinae/settings.json` is a snapshot |
| Zsh | `home/shell.nix` | Home Manager managed shell init | none | No direct `apply-theme` target |

## Neovim

### Structure

The Neovim tree is split into four layers:

- `init.lua` bootstraps `lazy.nvim`, loads the core config modules, and imports every plugin spec from `lua/plugins/`.
- `lua/config/` contains editor behavior: options, keymaps, filetype detection, autocmds, and LSP wiring.
- `lua/plugins/` is the plugin spec layer. It is grouped by concern: `colors.lua`, `completion.lua`, `editor.lua`, `lang.lua`, `lsp.lua`, and `ui.lua`.
- `after/ftplugin/` contains per-filetype local overrides for TeX, Plain TeX, and Markdown.

There are also two spelling artifacts:

- `spell/en.utf-8.add` is the custom word list.
- `spell/en.utf-8.add.spl` is the compiled binary spell file corresponding to it.

`lazy-lock.json` pins plugin revisions, so the configuration is repo-authored but the exact plugin state is also explicitly locked.

### Plugin And LSP Model

`init.lua` bootstraps `lazy.nvim` directly into `stdpath("data")/lazy/lazy.nvim`, then calls `require("lazy").setup(...)` with `defaults.lazy = true`. The tree is therefore a spec-driven lazy.nvim setup, not a Vim package tree and not a `vim.pack` setup.

LSP is configured in `lua/config/lsp.lua` with the Neovim 0.11+ core APIs:

- `vim.lsp.config(...)` to extend configs
- `vim.lsp.enable(...)` to enable them
- `cmp_nvim_lsp.default_capabilities(...)` to extend completion capabilities
- a shared `LspAttach` autocmd for buffer-local maps and `nvim-navic` attachment

The language servers themselves are not installed by Mason. They are installed by Nix in `home/default.nix`:

- `lua-language-server`
- `pyright`
- `texlab`
- `ltex-ls`

That means Neovim owns client behavior, but package lifecycle is outside Neovim and centralized in Nix.

### Theme Integration

Neovim uses the `standalone` theme strategy. The target in `themes/lib/targets/neovim.py` writes `~/.config/nvim/lua/theme-state.json` with only two fields:

- `colorscheme`
- `background`

`lua/plugins/colors.lua` reads that JSON at startup, sets `vim.o.background`, and then tries to `:colorscheme` the generated name. If that fails, it falls back to `gruvbox`.

This is intentionally much thinner than the other tool targets: the theme system does not generate highlight groups, plugin palettes, or Lua theme modules. It only hands Neovim a small state file and lets the runtime config interpret it.

### Notable Choices

- `ellisonleao/gruvbox.nvim` is the only colorscheme plugin currently installed.
- `lualine` and `barbecue` are both hardcoded to `theme = "gruvbox"`.
- Treesitter is pinned to the upstream `master` branch and includes a compatibility split between the legacy `nvim-treesitter.configs` path and a newer `require("nvim-treesitter").setup(...)` path.
- `vimtex` is configured for `latexmk` and Zathura, which ties Neovim directly to the TeX Live and Zathura setup managed elsewhere in the repo.

## Alacritty

### Structure

The repo-authored Alacritty config is intentionally small:

- `config/alacritty/alacritty.toml` defines stable behavior
- `~/.config/alacritty/theme.toml` is generated by `apply-theme`

The stable file only owns:

- the import statement
- window padding
- scrollback size and scroll multiplier

The generated file owns:

- terminal font family and size
- primary colors
- normal ANSI colors
- bright ANSI colors

### Theme Integration

Alacritty uses the cleanest split in this set: `import`.

`config/alacritty/alacritty.toml` imports `~/.config/alacritty/theme.toml`, and `themes/lib/targets/alacritty.py` writes that fragment. Because Alacritty watches config changes, the target declares no reload command.

Font choice is theme-managed here. The generated fragment includes both color data and the terminal font settings derived from `ThemeState`.

### Notable Choices

- Scrollback is set to `100000`, which is the documented ceiling in current Alacritty docs.
- Stable UI behavior and theme data are already separated cleanly; there is very little ambiguity about what is generated versus authored.

## Ghostty

### Structure

Ghostty is currently managed almost entirely by the theming layer:

- `config/ghostty/base` exists, but today it only contains comments
- `themes/lib/targets/ghostty.py` writes the live `~/.config/ghostty/config`
- the committed `config/ghostty/config` is a generated snapshot, not the file referenced by Home Manager

Unlike Alacritty, there is no Home Manager symlink that points `~/.config/ghostty/config` back at this repo. The canonical runtime file is whatever `apply-theme` last wrote.

### Theme Integration

Ghostty uses `concat`. In practice that means:

- read `config/ghostty/base`
- append generated font and color lines
- write the final file to `~/.config/ghostty/config`

Because the base file is currently empty aside from comments, the real behavior is very close to full-file generation.

The generated portion includes:

- `font-family`
- `font-size`
- `background` / `foreground`
- selection and cursor colors
- palette entries `0..15`

### Notable Choices

- Ghostty font settings are theme-managed, just like Alacritty.
- Only the first 16 palette slots are generated.
- The committed `config/ghostty/config` still carries an older `apply-theme.sh` header, which suggests it is a stale snapshot rather than a maintained source file.

## tmux

### Structure

tmux follows the same pattern as Alacritty and Zathura:

- `config/tmux/tmux.conf` is the stable repo-managed file
- `~/.config/tmux/colors.conf` is generated

The stable config owns:

- prefix and keybindings
- terminal defaults
- mouse mode
- history size
- window and pane indexing
- split behavior
- pane navigation
- config reload binding

The generated file owns only statusline and border colors.

### Theme Integration

tmux uses `import` assembly. `tmux.conf` ends with `source-file ~/.config/tmux/colors.conf`, and `themes/lib/targets/tmux.py` writes that file.

At runtime the target also declares a reload command:

- `tmux source-file ~/.config/tmux/colors.conf`

That means an interactive `apply-theme` run can update existing tmux sessions, while Home Manager activation uses `sync` and skips runtime reloads.

### Inter-Tool Relationships

tmux explicitly knows about the terminal emulators in this repo:

- `default-terminal` is set to `tmux-256color`
- `terminal-overrides` adds `RGB` support for `alacritty` and `ghostty`

So tmux is not isolated. It is tuned specifically for the terminal choices elsewhere in the dotfiles.

## Zsh

### Structure

Zsh is defined in `home/shell.nix` rather than in a repo-side `config/zsh/` tree. The file contains:

- `programs.zsh` module settings
- shell history settings
- completion setup
- autosuggestion and syntax-highlighting enablement
- aliases and helper functions
- inline `initContent`
- session variables and PATH
- adjacent tool enablement for Starship, Zoxide, fzf, eza, bat, and git

### Notable Choices

- `dotDir` relocates the shell dotfiles into XDG config space.
- history is redirected into XDG state space and shared across sessions.
- completion is explicitly initialized with a custom `compinit` cache path under `$XDG_CACHE_HOME`.
- the shell is the place where Starship is actually enabled for Zsh, but Starship's prompt structure still lives outside Nix in a generated config file.

## Starship

### Structure

Starship is split between Nix enablement and a generated runtime config:

- `home/shell.nix` enables Starship and its Zsh integration
- `config/starship/base.toml` contains the stable prompt layout and module choices
- `themes/lib/targets/starship.py` generates a palette block into `~/.config/starship.toml`

The committed `config/starship/starship.toml` is not referenced by Home Manager or by the target's `BASE_PATH`. It is a generated snapshot, not the active source file.

### Theme Integration

Starship uses `concat`. The base config provides the full prompt layout and refers to a palette name, while the target appends a generated `[palettes.current]` block.

A notable detail is that the target computes contrast-safe foreground colors for accent blocks, so Starship is not just receiving raw theme colors. It is receiving a small amount of extra accessibility logic as part of theme generation.

### Inter-Tool Relationships

- Starship is rendered inside Zsh because `programs.starship.enableZshIntegration = true`.
- The prompt assumes the same Nerd Font-capable terminal setup used by Alacritty and Ghostty.
- The Zsh layer also enables `zoxide`, `fzf`, `eza`, and `bat`, so the prompt sits inside a shell experience that is already structured around those tools.

## Zathura

### Structure

Zathura is minimal and clean:

- `config/zathura/zathurarc` contains the stable settings
- `~/.config/zathura/colors` is generated

The stable file only does two things:

- `set selection-clipboard clipboard`
- `include colors`

### Theme Integration

Zathura uses `import` assembly. The generator writes a color file with UI colors, completion colors, notifications, and recolor settings, and the base config includes it.

This is a straightforward split between stable behavior and generated theme data.

### Inter-Tool Relationships

Zathura is not just a standalone PDF viewer here. `vimtex` is configured to use it as Neovim's LaTeX viewer, so the Zathura config is part of the editor toolchain as well.

## Vicinae

### Structure

Vicinae is enabled through `services.vicinae.enable = true` in `home/default.nix`, but the theme-managed config is not symlinked from the repo. The relevant files are:

- `config/vicinae/base.json`
- `~/.config/vicinae/settings.json` written by `apply-theme`
- `config/vicinae/settings.json`, which is a committed snapshot of a generated file
- `config/vicinae/vicinae.json`, which is not referenced by the local Nix or theme code

`base.json` is small and only defines application-provider search paths for Nix and XDG application directories.

### Theme Integration

Vicinae uses `concat`, but for JSON targets that means a shallow merge:

- read `config/vicinae/base.json`
- generate a JSON object containing `font.normal.family` and `theme.dark/light`
- merge dicts one level deep
- write the result to `~/.config/vicinae/settings.json`

The target does not manage the whole launcher config. It only manages:

- system font family
- theme names for light and dark appearances

Everything else is expected to come either from the base JSON or from Vicinae defaults.

### Notable Choices

- The target maps global theme families to Vicinae built-in theme names via `_THEME_MAP`.
- The provider paths explicitly include user-level and system-level Nix desktop-entry locations, so the launcher is intentionally aware of the Nix profile layout.
- The repo contains two different Vicinae JSON snapshots with different schemas and different theme values, which makes the actual source of truth less obvious than for the other tools.

## Cross-Tool Relationships

Several relationships matter across these tool configs:

- Neovim LSP servers are installed by Nix, not by Mason, so package management is centralized outside the editor.
- VimTeX depends on both `latexmk` from the TeX Live package set and Zathura as the viewer.
- tmux is tuned specifically for Alacritty and Ghostty truecolor support.
- Starship is configured as a Zsh prompt, not as a standalone Nix-managed config blob.
- Vicinae searches Nix-managed application directories directly.
- Home Manager activation guarantees that the generated theme fragments exist before the session starts, while runtime theme changes go through the same `apply-theme` targets with live reloads where supported.

