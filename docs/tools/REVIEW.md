# Tools Configuration Review

Reviewed on 2026-04-19; updated 2026-06-10 after the fix pass.

## Verdict

The repo has a clear split between Nix-owned package lifecycle and repo-owned
runtime behavior. The remaining issues are now tool-specific places where the
implementation is narrower than the upstream tool surface.

## Tool Findings

| Severity | Tool | Finding |
| --- | --- | --- |
| Medium | Neovim | The Neovim 0.12 Treesitter path is much thinner than the 0.11 path and would change behavior materially if activated. |
| Low | Neovim | The pinned `pocco81/auto-save.nvim` upstream is archived (last commit 2022-11-01) and internally uses the deprecated `nvim_buf_get_option` API (works on 0.12, on the removal track). Kept knowingly (TOOLSCONFIGS-11); the maintained drop-in fork is `okuuva/auto-save.nvim` if the pin ever breaks (opts need a small translation: `trigger_events` becomes `immediate_save`/`defer_save` lists). |
| Medium | Zsh | `compinit -C` trades startup speed for skipping the new-functions and security checks once the dump exists. |
| Low | Zathura | Recolor is always enabled, which is coherent for dark-mode PDF reading but stronger than upstream defaults. |

The old "treesitter installs nothing" gap is closed: `gcc` is now in
`home/packages.nix` `basePackages` (comment: nvim treesitter parser
compilation), so `ensure_installed` / `:TSUpdate` compile parsers into
`~/.local/share/nvim/site/parser` on the next launch after a rebuild, and
`config/nvim/lua/plugins/lang.lua` warns once via `vim.notify_once` when no C
compiler is found instead of silently installing zero parsers. The 0.12-path
row above is unchanged and still accurate.

## Open Owner Questions

- `config/vscode/base.json` (TOOLSCONFIGS-9): it carries settings for
  extensions not installed on the desktop (gitlens, tabnine, markdownlint,
  github.copilot, liveServer) plus a `remote.SSH.remotePlatform` host list
  (`linux.cse.tamu.edu` and two LAN IPs). Kept as-is until the owner confirms
  what the laptop uses and which SSH hosts are still live.

Primary references were the current local configs plus the corresponding upstream
tool documentation for Neovim, Treesitter, VimTeX, Ghostty, tmux, Starship, Zsh
completion, Zathura, and Vicinae.
