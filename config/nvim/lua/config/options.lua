local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.termguicolors = true
opt.wrap = false
opt.signcolumn = "yes"
opt.splitbelow = true
opt.splitright = true
opt.ignorecase = true
opt.smartcase = true
opt.clipboard = "unnamedplus"
opt.hidden = true
opt.confirm = true
opt.updatetime = 250
opt.timeoutlen = 300

opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.expandtab = false
opt.smartindent = true
opt.autoindent = true

opt.spell = false
opt.spellfile = vim.fn.stdpath("config") .. "/spell/en.utf-8.add"

if vim.g.neovide then
  vim.o.guifont = "Comic Code:h12"
  vim.g.neovide_scale_factor = 0.9
end
