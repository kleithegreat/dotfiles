# Tools Configuration Review

## Scope

This review compares the current configs against current tool documentation and current plugin documentation where the Neovim config makes tool-level behavior depend on plugin behavior.

It covers:

- Neovim and the plugins that materially shape editor behavior
- Alacritty
- Ghostty
- tmux
- Zsh and Starship
- Zathura
- Vicinae

## Version Context

Local binaries in this environment report:

- Neovim `0.11.6`
- Alacritty `0.16.1`
- Ghostty `1.3.1`
- tmux `3.6a`
- Starship `1.24.2`
- Zsh `5.9`
- Zathura `2026.02.09`
- Vicinae `v0.20.9`

## Cross-Cutting Findings

### 1. The repo contains multiple stale generated snapshots

The cleanest configurations in this repo are the ones where the repo only stores the base fragment and `apply-theme` only writes the live generated file. Alacritty, tmux, and Zathura already follow that model well.

Ghostty, Starship, and Vicinae are less clear because the repo also contains committed generated outputs:

- `config/ghostty/config`
- `config/starship/starship.toml`
- `config/vicinae/settings.json`

Those files are not the inputs used by the active targets. The active inputs are:

- `config/ghostty/base`
- `config/starship/base.toml`
- `config/vicinae/base.json`

That has already drifted:

- `config/ghostty/config` still says `apply-theme.sh`
- `config/starship/starship.toml` no longer matches the current `starship` target, which now generates contrast-aware `*_fg` palette entries under `[palettes.current]`
- `config/vicinae/settings.json` does not match the current `themes/state.json`

This is mostly a documentation and maintenance problem, but it also makes reviews harder because the repo advertises more than one source of truth.

### 2. Theme integration quality is inconsistent across tools

The strongest theme integrations in this repo are the ones that use each tool's own include/import mechanism:

- Alacritty `import`
- tmux `source-file`
- Zathura `include`

Ghostty and Vicinae both have current first-class split-file mechanisms in their own docs, but the repo still treats them more like generated whole-file outputs.

## Neovim

### What already aligns well

- The LSP setup uses the current Neovim 0.11+ model: `vim.lsp.config(...)` and `vim.lsp.enable(...)`.
- `nvim-lspconfig` is used as a config source, not through the deprecated `require('lspconfig').setup(...)` API.
- Language servers are installed externally by Nix, which matches Neovim's own docs: Neovim ships the client, not the servers.
- Treesitter is correctly marked `lazy = false`, which matches `nvim-treesitter` guidance that the plugin does not support lazy-loading.

### Review notes

1. High: the Neovim theme target is not actually compatible with the full theme set in this repo.

`themes/lib/targets/neovim.py` writes:

- `"colorscheme": colors.family`
- `"background": colors.variant`

That only works for theme variants whose variant string is literally `light` or `dark`. Neovim's `background` option does not accept values like `mocha`, `night`, or `dawn`. This was confirmed locally with headless Neovim: `vim.o.background = "mocha"` and `vim.o.background = "night"` both raise `E474: Invalid argument`.

There is a second mismatch on the colorscheme side: the config only installs `gruvbox.nvim`, and `colors.lua` falls back to `gruvbox` if `:colorscheme <family>` fails. So the target can emit `solarized`, `catppuccin`, `nord`, `rosepine`, and `tokyonight`, but the runtime config only has a guaranteed implementation for `gruvbox`.

The UI layer reinforces that limitation:

- `lualine` hardcodes `theme = "gruvbox"`
- `barbecue` hardcodes `theme = "gruvbox"`

As written, Neovim is not a first-class consumer of the wider `themes/colors/*.json` catalog.

2. High: `vimtex` is lazy-loaded through the plugin manager even though VimTeX's own docs explicitly say not to do that.

The current spec is:

- `ft = { "tex", "plaintex", "bib" }`

VimTeX's README now recommends `lazy = false` under `lazy.nvim` and explicitly warns that plugin-manager lazy-loading breaks inverse search because `:VimtexInverseSearch` must exist globally. The rest of the VimTeX config is sensible, but the plugin-loading policy itself is out of line with upstream guidance.

3. Medium: the Neovim 0.12 Treesitter path is incomplete relative to the current `nvim-treesitter` docs.

For Neovim 0.11, the config still uses the older `nvim-treesitter.configs.setup(...)` path and enables:

- `ensure_installed`
- `highlight`
- `indent`
- `textobjects`

For Neovim 0.12+, the `setup_modern_treesitter()` branch only does:

- `require("nvim-treesitter").setup({ install_dir = ... })`

It does not install parsers, does not enable highlighting, and does not reapply the textobjects configuration. Current `nvim-treesitter` docs say those features are not auto-enabled. So the forward-compatibility branch exists, but it is much thinner than the legacy path and would change behavior materially if it ever became active.

4. Low: the LSP attach block duplicates several defaults that Neovim now already provides.

Current Neovim LSP defaults already set global mappings for `gri`, `grn`, `grr`, `grt`, `gO`, and insert-mode `CTRL-S`, and they also set buffer-local defaults such as `K`, `omnifunc`, `tagfunc`, and `formatexpr` when applicable.

The current config is not wrong for overriding those intentionally, but it is now carrying more keymap surface area than strictly necessary. If the intent is "custom-only", this block can shrink.

5. Low: the config does not currently opt into the optional LSP features that the core docs call out explicitly.

Neovim's own LSP quickstart now points to optional features such as:

- inlay hints
- linked editing ranges
- inline completion
- codelens

None of those are enabled here. That is a valid choice, but it is worth calling out because the core docs now present them as normal opt-in capabilities rather than rare extras.

6. Low: `nvim-cmp` warns that `cmp.mapping.preset.*` can change without announcement, and the config uses `cmp.mapping.preset.insert(...)`.

This is a stability tradeoff, not a bug. If exact key behavior should stay frozen across `nvim-cmp` updates, the mappings should be spelled out directly instead of using the preset helper.

## Alacritty

### What already aligns well

- The config structure matches current Alacritty docs very closely: a stable `alacritty.toml` plus imported generated fragment.
- No deprecated options were found in the current file.
- The use of `import` is exactly the documented mechanism for split config.
- Relying on live reload by default is consistent with current Alacritty behavior.

### Review notes

1. No material documentation issues found.

The separation is already the shape Alacritty recommends:

- stable behavior in the main config
- generated font and palette data in an imported file

2. Low: `history = 100000` is set to Alacritty's documented cap.

That is not wrong, but it is a deliberate choice rather than a neutral default.

## Ghostty

### What already aligns well

- The config uses valid current Ghostty keys such as `font-family`, `font-size`, `background`, and `palette = N=#...`.
- The target relies on Ghostty's documented live reload behavior.

### Review notes

1. Medium: Ghostty's own docs support `config-file` includes, but the repo does not use them.

Current Ghostty docs document `config-file` specifically for splitting configuration across multiple files. That is the closest equivalent to Alacritty's `import` and Zathura's `include`.

In this repo:

- the live file is generated directly at `~/.config/ghostty/config`
- `config/ghostty/base` is effectively empty
- the committed `config/ghostty/config` is just a snapshot

That means Ghostty is conceptually using `concat`, but functionally it is almost full-file generation. A cleaner design would be:

- stable main config in `config/ghostty/config`
- generated theme fragment in a second file
- `config-file = ...` to load it

2. Low: the theme target only sets the ANSI 16-color palette, not the extended palette strategy Ghostty now documents.

Ghostty 1.3 documents `palette-generate` as the option for deriving the 16-255 palette from the base ANSI colors. The current config does not set it, so the extended palette remains at Ghostty's default behavior rather than being theme-derived.

That is a reasonable compatibility choice, because Ghostty also documents why `palette-generate` is off by default. But if the goal is tighter theme cohesion for palette-heavy TUI apps, this is the knob to consider.

3. Low: if you want the GTK/Linux titlebar to follow the terminal theme more tightly, Ghostty now documents `window-theme = ghostty`.

The current config leaves the default `auto` behavior. That is fine, but it means the titlebar is less directly coupled to the generated background and foreground than it could be.

4. Low: the committed generated snapshot is visibly stale.

`config/ghostty/config` still says `Generated by apply-theme.sh`, while the current pipeline is `themes/apply-theme` via the orchestrator. That is another sign that the checked-in snapshot is no longer authoritative.

## tmux

### What already aligns well

- `default-terminal "tmux-256color"` is the right modern baseline.
- The base/generated split is clear and maintainable.
- Mouse mode, history size, indexing, and split behavior all use current tmux options.

### Review notes

1. Medium: modern tmux docs steer truecolor capability toward `terminal-features`, not `terminal-overrides`.

Current tmux docs describe `terminal-features` as the right place for named terminal capabilities like `RGB`, and they describe `terminal-overrides` as the lower-level escape hatch for raw terminfo capability overrides.

The current file uses:

- `set -ag terminal-overrides ",alacritty:RGB,ghostty:RGB"`

That still works, but on tmux `3.6a` the more current expression is:

- `set -as terminal-features ",alacritty:RGB,ghostty:RGB"`

2. Low: the theme dependency map says `mono_font` changes affect `tmux`, but the tmux target does not consume font state at all.

This is not a tmux config bug. It is a small theming-system mismatch in `themes/lib/orchestrator.py`. Changing `mono_font` should not need to rewrite the tmux colors file.

## Zsh

### What already aligns well

- The Home Manager layout is sensible: history in XDG state, cache in XDG cache, dotfiles in XDG config.
- `zsh-history-substring-search`, autosuggestions, syntax highlighting, fzf, zoxide, bat, and eza are all wired in coherent places.
- No deprecated Zsh options were found in the current shell config.

### Review notes

1. Medium: `compinit -C` is a startup-speed optimization with a real tradeoff.

The Zsh completion docs say `compinit -C` skips the "new functions" check and also skips the security check entirely when the dumpfile already exists. That means this config will start quickly, but if completion functions change or an insecure completion path appears, the cache will not self-correct until the dump is rebuilt manually.

That may be an intentional tradeoff, but it is worth documenting because it is not behaviorally neutral.

## Starship

### What already aligns well

- The config uses Starship's documented palette mechanism instead of hardcoding repeated hex values into every module.
- Enabling `os` and `time` explicitly is fine; both are disabled by default upstream, but the config turns them on intentionally.
- The target adds a useful contrast layer for accent foregrounds, which improves on a naive palette dump.

### Review notes

1. Medium: the committed `config/starship/starship.toml` is stale relative to the actual base-plus-generator model.

The active model is:

- `config/starship/base.toml`
- generated `[palettes.current]` block from `themes/lib/targets/starship.py`

But the committed generated file still shows the older merged result:

- `palette = 'gruvbox_dark'`
- no `color_*_fg` contrast entries
- a different set of module foreground choices

That makes the repo look like it has two Starship configs when only one model is real.

2. Low: if prompt latency becomes noticeable, current Starship docs recommend the global `scan_timeout` and `command_timeout` knobs.

Nothing in the current config is invalid, but those are the first documented performance levers if the prompt ever feels too heavy.

## Zathura

### What already aligns well

- The base file uses Zathura's documented `include` mechanism.
- `selection-clipboard clipboard` is still a valid current option.
- No deprecated Zathura options were found in the current file.

### Review notes

1. Low: recolor is permanently enabled even though the documented default is off.

The generated color file sets:

- `recolor "true"`
- `recolor-keephue "false"`
- `recolor-lightcolor`
- `recolor-darkcolor`

That is a coherent dark-mode style choice, but it is stronger than upstream defaults. If light themes or image-heavy PDFs ever look wrong, this is the first place to revisit. A variant-sensitive recolor policy would be closer to the spirit of the defaults.

## Vicinae

### What already aligns well

- The theme target writes current-schema keys for `font.normal.family` and `theme.dark/light`.
- The provider-path override in `base.json` is well adapted to a Nix system and should improve application discovery.

### Review notes

1. Medium: current Vicinae supports imported config fragments, but the repo still uses merge-based generation.

`vicinae config default` now documents an `imports` array for loading multiple config files. That means Vicinae has a first-class split-file mechanism, but the repo still uses:

- base JSON in `config/vicinae/base.json`
- generated JSON merged into `~/.config/vicinae/settings.json`

Using Vicinae's own import mechanism would make this tool look much more like Alacritty, tmux, and Zathura and would remove the need for the repo-side shallow JSON merge logic.

2. Medium: `_THEME_MAP` does not cover all theme family names that exist in `themes/colors/`.

The repo's color families currently include:

- `catppuccin`
- `gruvbox`
- `nord`
- `rosepine`
- `solarized`
- `tokyonight`

But `_THEME_MAP` only includes explicit entries for:

- `rose-pine`
- `tokyo-night`

So `rosepine` and `tokyonight` fall back to synthesized names like `rosepine-dark` or `tokyonight-night` rather than using explicit mapped names.

3. Medium: `config/vicinae/vicinae.json` appears to be a legacy config snapshot with an older schema.

The current Vicinae default config uses keys such as:

- `close_on_focus_loss`
- `consider_preedit`
- `pop_to_root_on_close`
- `favicon_service`
- `launcher_window`

But `config/vicinae/vicinae.json` uses older camelCase and older structure:

- `closeOnFocusLoss`
- `considerPreedit`
- `popToRootOnClose`
- `faviconService`
- `window`
- `font.size`
- single `theme.name`

No local Nix code or theme target references `config/vicinae/vicinae.json`, so it currently acts more like an archival file than an active config.

4. Medium: the committed `config/vicinae/settings.json` does not match the current theme state.

`themes/state.json` currently says `gruvbox-dark`, but the committed `config/vicinae/settings.json` still points both light and dark to `solarized-light`. That is another case where the committed generated snapshot is no longer trustworthy.

5. Low: the Vicinae theme target only manages a small subset of what current Vicinae can theme.

The generator currently manages:

- `font.normal.family`
- `theme.dark.name`
- `theme.light.name`

Current Vicinae defaults also expose:

- `font.normal.size`
- `launcher_window.opacity`
- `launcher_window.blur`
- `launcher_window.client_side_decorations.rounding`

Whether those should become theme-managed is a design choice, but the current integration is intentionally narrower than the application now supports.

## Sources

Primary documentation consulted:

- Neovim `:help` docs: <https://neovim.io/doc/user/lsp/> and <https://neovim.io/doc/user/pack/>
- Neovim wiki: <https://github.com/neovim/neovim/wiki>
- `nvim-lspconfig`: <https://github.com/neovim/nvim-lspconfig>
- `nvim-treesitter`: <https://github.com/nvim-treesitter/nvim-treesitter>
- `nvim-cmp`: <https://github.com/hrsh7th/nvim-cmp>
- `vimtex`: <https://github.com/lervag/vimtex>
- Alacritty config docs: <https://alacritty.org/releases/0.14.0/config-alacritty.html>
- Ghostty config docs: <https://ghostty.org/docs/config> and <https://ghostty.org/docs/config/reference>
- tmux wiki: <https://github.com/tmux/tmux/wiki>
- tmux manpage reference: <https://man.openbsd.org/OpenBSD-6.0/tmux.1>
- Starship config docs: <https://starship.rs/config/>
- Zathura manpage reference: <https://manpages.debian.org/testing/zathura/zathurarc.5>
- Zsh completion docs: <https://zsh.sourceforge.io/Doc/Release/Completion-System.html>
- Vicinae docs: <https://docs.vicinae.com/> and <https://docs.vicinae.com/launcher-window>

Local command/documentation cross-checks:

- `man 5 alacritty`
- `ghostty +show-config --default --docs`
- `man tmux`
- `man zathurarc`
- `vicinae config default`
- `vicinae version`

