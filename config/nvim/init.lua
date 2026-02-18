-- File: init.lua
-- Main entry point for Neovim configuration
-- This file bootstraps lazy.nvim and loads other configuration files

vim.cmd('cd /home/kevin/second-brain')
vim.o.guifont = "Comic Code:h12"
vim.o.background = "dark"

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

vim.api.nvim_create_autocmd({"FileType"}, {
  pattern = {"tex", "latex"},
  callback = function()
      vim.cmd('TSDisable highlight')  -- Disable Treesitter for TeX files
      vim.cmd('syntax enable')  -- Enable VimTeX syntax
      
      vim.opt_local.conceallevel = 2  -- Configure concealment (optional)
      vim.opt_local.concealcursor = 'c'
      vim.opt_local.spell = true
      vim.opt_local.spelllang = "en_us"
      vim.opt_local.wrap = true
      vim.opt_local.linebreak = true
      vim.opt_local.textwidth = 0
  end,
})

vim.g.neovide_scale_factor = 0.9

-- Add word wrap specifically for Markdown files
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
      vim.opt_local.wrap = true           -- Enable line wrapping
      vim.opt_local.linebreak = true      -- Break lines at word boundaries
      vim.opt_local.textwidth = 0        -- Set text width to 80 characters
      vim.opt_local.spell = true
      vim.opt_local.spelllang = "en_us"
  end,
  group = vim.api.nvim_create_augroup("markdown_settings", { clear = true })
})

vim.filetype.add({
  pattern = { [".*/hypr/.*%.conf"] = "hyprlang" },
})