# Tools Configuration Review

Reviewed on 2026-04-19.

## Verdict

The repo has a clear split between Nix-owned package lifecycle and repo-owned
runtime behavior. The remaining issues are now tool-specific places where the
implementation is narrower than the upstream tool surface.

## Tool Findings

| Severity | Tool | Finding |
| --- | --- | --- |
| Medium | Neovim | The Neovim 0.12 Treesitter path is much thinner than the 0.11 path and would change behavior materially if activated. |
| Low | Neovim | The editor remains intentionally single-scheme: non-`gruvbox` theme state now falls back silently to `gruvbox` instead of trying to load arbitrary scheme names. |
| Medium | Zsh | `compinit -C` trades startup speed for skipping the new-functions and security checks once the dump exists. |
| Low | Zathura | Recolor is always enabled, which is coherent for dark-mode PDF reading but stronger than upstream defaults. |

Primary references were the current local configs plus the corresponding upstream
tool documentation for Neovim, Treesitter, VimTeX, Ghostty, tmux, Starship, Zsh
completion, Zathura, and Vicinae.
