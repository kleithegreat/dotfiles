{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    withPython3 = false;
    withRuby = false;
    # The repo owns ~/.config/nvim/init.lua; this moves home-manager's own lines onto --cmd.
    sideloadInitLua = true;
    plugins = with pkgs.vimPlugins; [
      blink-cmp
      markdown-preview-nvim
      mini-nvim
      nvim-lspconfig
      (nvim-treesitter.withPlugins (p: [
        p.bash
        p.cpp
        p.css
        p.haskell
        p.html
        p.hyprlang
        p.javascript
        p.json
        p.make
        p.nix
        p.python
        p.qmljs
        p.regex
        p.rust
        p.sql
        p.toml
        p.typescript
        p.yaml
        pkgs.tree-sitter-bend2
      ]))
      nvim-treesitter-textobjects
      vimtex
    ];
    extraPackages = with pkgs; [
      bend2-lsp
      copilot-language-server
      lua-language-server
      nixd
      pyright
      texlab
    ];
  };
}
