# Tools

## Intent

- Every managed tool config is one of two things: a **base file** — repo-
  authored under `config/<tool>/`, read-only to the theme pipeline, edited by
  humans — or a **generated output** — pipeline-owned, written to `~/.config/`
  (or the app's own path) on theme apply, silently overwritten, never
  hand-edited. A base file and its generated output are never the same path.
- A tool gets a `config/<tool>/` subdirectory when it has user-authored
  runtime config in its own file format. It stays pure-Nix (Home Manager
  `programs.*`) when the Nix module covers its useful surface (fzf, zoxide,
  eza) — a `config/` dir there would just duplicate the module. Tools with
  both (Neovim, Starship) use Nix for the package and `config/` for behavior.
  A Nix-authored tool may still source a generated fragment (zsh sources
  `~/.config/zsh/theme-colors` from `programs.zsh.initContent`).
- Generated outputs are never committed. Do not reintroduce committed concat
  outputs or snapshot files under `config/`.
- Zsh history is single and global. Per-directory history was tried and
  removed: fish, the model being copied, records no cwd and partitions
  nothing, and the plugin also fights `history.share`. The fish-like part
  that is actually wanted is ↑/↓ on `zsh-history-substring-search`
  plus autosuggestions over one history file.

## Quirks

### Zsh plugins are sourced before `HISTFILE` is set
Home Manager's zsh module emits `programs.zsh.plugins` above its own
`HISTFILE=` assignment in the generated `.zshrc`, so a plugin that reads
`$HISTFILE` at load time captures zsh's built-in `~/.zsh_history` rather
than `history.path`. The failure is silent — history keeps working, it just
accumulates in a file nothing else reads. `zsh-per-directory-history` hit
this and is gone. Source any history-aware plugin from `initContent`, which
lands after the assignment; do not add it to `plugins`.

### Generated files inside symlinked trees are absent until first theme sync
Base configs reference generated files that don't exist on a fresh clone
(`~/.config/hypr/colors.lua`, `nvim/lua/theme-colors.lua`,
`quickshell/GeneratedTheme.json`, `zsh/theme-colors`, the per-app theme
fragments). They are not missing repo files — `desktopctl theme sync` during
Home Manager activation creates them. Do not add placeholders to `config/`.
Quickshell's `Theme.qml` carries built-in fallbacks for the pre-sync window.

### The Neovim spellfile is a read-only store symlink
`zg`/`zw` fail with E510 because `~/.config/nvim` is a store symlink. Add
words by editing `config/nvim/spell/en.utf-8.add` in the repo, regenerating
the `.spl` with `nvim -u NONE -c 'mkspell! config/nvim/spell/en.utf-8.add' -c q`,
and committing both. Doc-only handling per owner decision; the proposed future
fix is seeding a writable copy under `stdpath("data")/spell`.

### `lazy-lock.json` is a writable out-of-store symlink on purpose
`home/xdg.nix` deploys `config/nvim` from the store but points `lazy-lock.json`
at the checkout via `mkOutOfStoreSymlink` (assuming `~/repos/dotfiles`), so
`:Lazy update` writes the committed lock directly — review the diff and
commit. On a host without the checkout at that path the symlink dangles and
lazy.nvim recreates the lock; clone first.

### auto-save.nvim is pinned to an archived upstream knowingly
`pocco81/auto-save.nvim` is archived and uses a deprecated API that still
works on 0.12. If the pin breaks, the drop-in fork is `okuuva/auto-save.nvim`
(opts translation: `trigger_events` becomes `immediate_save`/`defer_save`
lists).

### Vicinae provider search paths stay literal
`config/vicinae/settings.json` contains absolute `/home/kevin/...` paths
because Vicinae documents no `~`/env expansion for
`providers.*.preferences.paths` (only top-level `imports` take relative
paths). Do not "fix" them, and do not add comments — the file must stay strict
JSON. Also: the desktopctl target writes custom theme TOMLs to
`~/.local/share/vicinae/themes/`, which *override* Vicinae's packaged themes
of the same ID — inspect there when a "built-in" theme shows managed colors —
and it writes the icon theme into both `theme.light`/`theme.dark` variants
because Vicinae otherwise falls back to its own icon-theme heuristic.

Related: [[theming]], [[nix]], [[hyprland]]
