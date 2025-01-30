-- File: init.lua
-- Main entry point for Neovim configuration
-- This file bootstraps lazy.nvim and loads other configuration files

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