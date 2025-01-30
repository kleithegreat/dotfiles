-- File: init.lua
-- Main entry point for Neovim configuration
-- This file bootstraps lazy.nvim and loads other configuration files

vim.cmd('cd /home/kevin/second-brain')
vim.o.guifont = "JetBrainsMono Nerd Font:h12"

-- Set leader key to space (do this before lazy setup)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Bootstrap lazy.nvim package manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Load core configurations
require("options")  -- Load basic vim options and keymaps

-- Initialize lazy.nvim with plugins
require("lazy").setup("plugins")

-- In init.lua or autocmd.lua
vim.api.nvim_create_autocmd({"FileType"}, {
  pattern = {"tex", "latex"},
  callback = function()
      -- Disable Treesitter for TeX files
      vim.cmd('TSDisable highlight')
      
      -- Enable VimTeX syntax
      vim.cmd('syntax enable')
      
      -- Configure concealment (optional)
      vim.opt_local.conceallevel = 2
      vim.opt_local.concealcursor = 'c'
      
      -- Other LaTeX-specific settings
      vim.opt_local.spell = true
      vim.opt_local.spelllang = "en_us"
  end,
})

vim.g.neovide_scale_factor = 0.9