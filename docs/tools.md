# Tools

## Intent

- A managed tool config is either a **base file** — repo-authored, read-only to
  the theme pipeline (`styling/bases/` when desktopctl merges it, else
  `config/<tool>/`) — or a **generated output**, written on theme apply and
  never hand-edited or committed. They are never the same path.
- A tool gets `config/<tool>/` only for its own config format; Home Manager
  `programs.*` covers the rest. A Nix-authored tool may still source a
  generated fragment (zsh's `theme-colors`).
- Zsh history is single and global: substring search and autosuggestions over
  one file. Per-directory history fights `history.share`.

## Quirks

### Zsh plugins are sourced before `HISTFILE` is set
A history-aware plugin in `programs.zsh.plugins` silently uses
`~/.zsh_history`; source it from `initContent`.

### Generated files are absent until the first theme sync
`colors.lua`, `theme-colors.lua`, `GeneratedTheme.json`, `zsh/theme-colors` and
friends come from `desktopctl theme sync` at activation. Don't add
placeholders; `Theme.qml` has fallbacks for the window before it.

### The Neovim spellfile is a read-only store symlink
`zg`/`zw` fail with E510. Edit `config/nvim/spell/en.utf-8.add`, regenerate
with `nvim -u NONE -c 'mkspell! config/nvim/spell/en.utf-8.add' -c q`, commit
both.

### `lazy-lock.json` is a writable out-of-store symlink on purpose
`:Lazy update` writes the committed lock in `~/repos/dotfiles`; review and
commit. Without the checkout there it dangles.

### auto-save.nvim is pinned to an archived upstream knowingly
If it breaks, the drop-in fork is `okuuva/auto-save.nvim` (`trigger_events`
becomes `immediate_save`/`defer_save`).

### Vicinae provider paths stay literal
`config/vicinae/settings.json` has absolute `/home/kevin/...` paths: there is
no `~`/env expansion there, and the file must stay strict JSON (no comments).
