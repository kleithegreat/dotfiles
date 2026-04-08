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

local function normalize_background(background)
  if background == "dark" or background == "light" then
    return background
  end

  return nil
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
      local background = state and normalize_background(state.background)
      if background then
        vim.o.background = background
      end

      local colorscheme = "gruvbox"
      if state and state.colorscheme == "gruvbox" then
        colorscheme = state.colorscheme
      end

      vim.cmd.colorscheme(colorscheme)
    end,
  },
}
