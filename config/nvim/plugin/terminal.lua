local buf, win

local function toggle()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_hide(win)
    return
  end

  local fresh = not (buf and vim.api.nvim_buf_is_valid(buf))
  local dir = vim.fn.expand("%:p:h")
  if fresh then
    buf = vim.api.nvim_create_buf(false, true)
  end

  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.8)
  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
  })

  if fresh then
    vim.fn.jobstart({ vim.o.shell }, { term = true, cwd = vim.fn.isdirectory(dir) == 1 and dir or nil })
  end
  vim.cmd.startinsert()
end

vim.keymap.set("n", "<leader>t", toggle, { desc = "Terminal" })
