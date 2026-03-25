local uv = vim.uv or vim.loop

vim.g.mapleader = " "
vim.g.maplocalleader = " "

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("config.options")
require("config.keymaps")
require("config.filetypes")
require("config.autocmds")

require("lazy").setup({
  { import = "plugins" },
}, {
  defaults = {
    lazy = true,
  },
  install = {
    colorscheme = { "gruvbox" },
  },
})
