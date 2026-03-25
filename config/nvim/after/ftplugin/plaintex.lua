pcall(vim.treesitter.stop)
vim.bo.syntax = "tex"

vim.opt_local.conceallevel = 2
vim.opt_local.concealcursor = "c"
vim.opt_local.wrap = true
vim.opt_local.linebreak = true
vim.opt_local.textwidth = 0
vim.opt_local.spell = true
vim.opt_local.spelllang = { "en_us" }
