local buf, win

local function toggle()
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_hide(win)
    return
  end

  local alive = buf and vim.api.nvim_buf_is_valid(buf)
  if alive then
    local chan = vim.bo[buf].channel
    alive = chan > 0 and vim.fn.jobwait({ chan }, 0)[1] == -1
  end
  local fresh = not alive
  local dir = vim.fn.expand("%:p:h")
  if fresh then
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
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

vim.keymap.set({ "n", "t" }, "<leader>t", toggle, { desc = "Terminal" })
