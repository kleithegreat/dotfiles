local function load_theme_state()
  local path = vim.fn.stdpath("config") .. "/lua/theme-state.json"
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok or not data or vim.tbl_isempty(data) then
    return nil
  end

  local decoded_ok, state = pcall(vim.json.decode, table.concat(data, "\n"))
  if not decoded_ok then
    return nil
  end

  return state
end

return {
  {
    "ellisonleao/gruvbox.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent_mode = false,
    },
    config = function(_, opts)
      require("gruvbox").setup(opts)

      local state = load_theme_state()
      if state and state.background then
        vim.o.background = state.background
      end

      local colorscheme = state and state.colorscheme or "gruvbox"
      local ok = pcall(vim.cmd.colorscheme, colorscheme)
      if not ok then
        vim.cmd.colorscheme("gruvbox")
      end
    end,
  },
}
