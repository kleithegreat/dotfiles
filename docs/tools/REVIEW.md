# Tools Configuration Review

Reviewed on 2026-04-08.

## Verdict

The repo has a clear split between Nix-owned package lifecycle and repo-owned
runtime behavior. The main remaining issues are tool-specific places where the
implementation is narrower than the upstream tool surface.

## Cross-Cutting Findings

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | Not every tool uses the application's own split-file mechanism even when one exists. | Ghostty and Vicinae could look more like Alacritty, tmux, and Zathura if their native include/import models were used. |

## Tool Findings

| Severity | Tool | Finding |
| --- | --- | --- |
| Medium | Neovim | The Neovim 0.12 Treesitter path is much thinner than the 0.11 path and would change behavior materially if activated. |
| Low | Neovim | The editor remains intentionally single-scheme: non-`gruvbox` theme state now falls back silently to `gruvbox` instead of trying to load arbitrary scheme names. |
| Medium | Ghostty | The current design is close to full-file generation even though Ghostty supports split config through `config-file`. |
| Medium | Zsh | `compinit -C` trades startup speed for skipping the new-functions and security checks once the dump exists. |
| Medium | Vicinae | Vicinae supports imported fragments, but the repo still uses merge-based generation. |
| Low | Zathura | Recolor is always enabled, which is coherent for dark-mode PDF reading but stronger than upstream defaults. |

Primary references were the current local configs plus the corresponding upstream
tool documentation for Neovim, Treesitter, VimTeX, Ghostty, tmux, Starship, Zsh
completion, Zathura, and Vicinae.
