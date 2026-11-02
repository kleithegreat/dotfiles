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
- `pkgs/tree-sitter-bend2` mirrors the parser in `bend2/bend.ts` of the Bend
  release its `version` names, glue and column rules included, rather than
  approximating the syntax. A Bend bump re-checks it against that release.
- Neovim's plugins, tree-sitter grammars and language servers all come from
  `home/neovim.nix`; nothing is fetched or compiled at runtime. The Lua config
  leans on Neovim's defaults (`gr*` LSP maps, `[d`/`]d`, `an`/`in`) and adds a
  plugin only where the built-in falls short.

## Quirks

### Zsh plugins are sourced before `HISTFILE` is set
A history-aware plugin in `programs.zsh.plugins` silently uses
`~/.zsh_history`; source it from `initContent`.

### Generated files are absent until the first theme sync
`colors.lua`, `theme-colors.lua`, `GeneratedTheme.json`, `zsh/theme-colors` and
friends come from `desktopctl theme sync` at activation. Don't add
placeholders; `Theme.qml` has fallbacks for the window before it.

### The Neovim spell dir is a writable out-of-store symlink on purpose
`zg`/`zw` write `config/nvim/spell/` in `~/repos/dotfiles`; commit both files.
Without the checkout there it dangles.

### About 90 of Bend's own `.bend` files fail the Bend grammar by design
They are tests whose expected output (`#|` lines) is an `Error:`. The grammar
is right when every `.bend` file in the release without one parses cleanly.

### Vicinae provider paths stay literal
`config/vicinae/settings.json` has absolute `/home/kevin/...` paths: there is
no `~`/env expansion there, and the file must stay strict JSON (no comments).
