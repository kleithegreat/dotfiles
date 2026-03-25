local function map(mode, lhs, rhs, desc, opts)
  local options = vim.tbl_extend("force", {
    silent = true,
    desc = desc,
  }, opts or {})

  vim.keymap.set(mode, lhs, rhs, options)
end

map("n", "<Tab>", "<cmd>bnext<cr>", "Next buffer")
map("n", "<S-Tab>", "<cmd>bprevious<cr>", "Previous buffer")
map("n", "<leader>bd", function()
  vim.cmd.bdelete()
end, "Delete buffer")
map("n", "<leader>b", "<cmd>buffers<cr>:buffer ", "Switch buffer", { silent = false })

map("n", "<leader>sv", "<cmd>vsplit<cr>", "Vertical split")
map("n", "<leader>sh", "<cmd>split<cr>", "Horizontal split")

map("n", "<C-Up>", "<cmd>resize +2<cr>", "Increase window height")
map("n", "<C-Down>", "<cmd>resize -2<cr>", "Decrease window height")
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", "Decrease window width")
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", "Increase window width")

map("t", "<Esc>", [[<C-\><C-n>]], "Exit terminal mode")
