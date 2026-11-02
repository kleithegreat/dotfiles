vim.g.mapleader = " "

vim.o.number = true
vim.o.relativenumber = true
vim.o.signcolumn = "yes"
vim.o.showmode = false
vim.o.wrap = false
vim.o.linebreak = true
vim.o.breakindent = true
vim.o.scrolloff = 4
vim.o.splitbelow = true
vim.o.splitright = true
vim.o.winborder = "rounded"
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.tabstop = 4
vim.o.clipboard = "unnamedplus"
vim.o.undofile = true
vim.o.confirm = true
vim.o.updatetime = 250
vim.o.timeoutlen = 300
vim.o.spelllang = "en_us"

vim.g.tex_flavor = "latex"
vim.filetype.add({ extension = { bend = "bend" } })

vim.cmd.colorscheme("desktopctl")
if vim.g.neovide then
  pcall(require, "neovide-theme")
end

vim.diagnostic.config({ severity_sort = true, virtual_text = true })

vim.keymap.set("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Leave terminal mode" })

local group = vim.api.nvim_create_augroup("init", {})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  desc = "Start treesitter where a parser exists",
  callback = function(args)
    local lang = vim.treesitter.language.get_lang(args.match)
    if lang and vim.treesitter.language.add(lang) then
      vim.treesitter.start(args.buf, lang)
    end
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "markdown", "tex", "text", "gitcommit" },
  desc = "Soft-wrap and spellcheck prose",
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})

vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "FocusLost" }, {
  group = group,
  desc = "Auto-save",
  callback = function(args)
    local bo = vim.bo[args.buf]
    if bo.buftype == "" and bo.modified and not bo.readonly and vim.api.nvim_buf_get_name(args.buf) ~= "" then
      vim.api.nvim_buf_call(args.buf, function()
        vim.cmd("silent update")
      end)
    end
  end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  desc = "Flash yanked text",
  callback = function()
    vim.hl.on_yank()
  end,
})
