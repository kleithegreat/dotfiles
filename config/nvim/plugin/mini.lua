require("mini.icons").setup()
require("mini.statusline").setup()
require("mini.pairs").setup()
require("mini.diff").setup()
require("mini.files").setup()
require("mini.extra").setup()

local pick = require("mini.pick")
pick.setup()
vim.ui.select = pick.ui_select

local ai = require("mini.ai")
ai.setup({
  custom_textobjects = {
    f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
    c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
  },
})

local clue = require("mini.clue")
clue.setup({
  triggers = {
    { mode = { "n", "x" }, keys = "<Leader>" },
    { mode = { "n", "x" }, keys = "<LocalLeader>" },
    { mode = { "n", "x" }, keys = "g" },
    { mode = { "n", "x" }, keys = "z" },
    { mode = { "n", "x" }, keys = "'" },
    { mode = { "n", "x" }, keys = "`" },
    { mode = { "n", "x" }, keys = '"' },
    { mode = { "i", "c" }, keys = "<C-r>" },
    { mode = "i", keys = "<C-x>" },
    { mode = "n", keys = "<C-w>" },
    { mode = "n", keys = "[" },
    { mode = "n", keys = "]" },
  },
  clues = {
    clue.gen_clues.builtin_completion(),
    clue.gen_clues.g(),
    clue.gen_clues.marks(),
    clue.gen_clues.registers(),
    clue.gen_clues.square_brackets(),
    clue.gen_clues.windows(),
    clue.gen_clues.z(),
  },
})

local function map(lhs, rhs, desc)
  vim.keymap.set("n", lhs, rhs, { desc = desc })
end

local pickers = MiniExtra.pickers

map("<leader>f", pick.builtin.files, "Find file")
map("<leader>/", pick.builtin.grep_live, "Grep")
map("<leader>*", function()
  pick.builtin.grep({ pattern = vim.fn.expand("<cword>") })
end, "Grep word under cursor")
map("<leader>b", pick.builtin.buffers, "Buffers")
map("<leader>r", pickers.oldfiles, "Recent files")
map("<leader>h", pick.builtin.help, "Help")
map("<leader>k", pickers.keymaps, "Keymaps")
map("<leader>'", pick.builtin.resume, "Resume last picker")
map("<leader>d", pickers.diagnostic, "Diagnostics")
map("<leader>s", function()
  pickers.lsp({ scope = "document_symbol" })
end, "Symbols in file")
map("<leader>S", function()
  pickers.lsp({ scope = "workspace_symbol" })
end, "Symbols in workspace")
map("<leader>g", pickers.git_hunks, "Git hunks")
map("<leader>o", MiniDiff.toggle_overlay, "Toggle diff overlay")
map("<leader>e", function()
  local path = vim.api.nvim_buf_get_name(0)
  MiniFiles.open(vim.uv.fs_stat(path) and path or nil)
end, "File explorer")
