local uv = vim.uv or vim.loop

local function current_buffer_dir()
  local dir = vim.fn.expand("%:p:h")
  if dir == "" then
    return uv.cwd()
  end
  return dir
end

return {
  {
    "nvim-tree/nvim-tree.lua",
    cmd = {
      "NvimTreeFindFile",
      "NvimTreeFindFileToggle",
      "NvimTreeFocus",
      "NvimTreeToggle",
    },
    keys = {
      { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "Toggle file tree" },
    },
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      update_focused_file = {
        enable = true,
      },
      view = {
        width = 36,
        preserve_window_proportions = true,
      },
      git = {
        ignore = false,
      },
    },
  },
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    keys = {
      {
        "<leader>ff",
        function()
          require("telescope.builtin").find_files()
        end,
        desc = "Find files",
      },
      {
        "<leader>fg",
        function()
          require("telescope.builtin").live_grep()
        end,
        desc = "Live grep",
      },
      {
        "<leader>fb",
        function()
          require("telescope.builtin").buffers()
        end,
        desc = "Find buffers",
      },
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    opts = {
      defaults = {
        path_display = { "smart" },
      },
    },
  },
  {
    "pocco81/auto-save.nvim",
    event = { "InsertLeave", "TextChanged" },
    opts = {
      enabled = true,
      trigger_events = { "InsertLeave", "TextChanged" },
      write_all_buffers = false,
      debounce_delay = 150,
      condition = function(buf)
        return vim.bo[buf].modifiable and vim.bo[buf].buftype == ""
      end,
    },
  },
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    cmd = { "ToggleTerm", "TermExec" },
    keys = {
      {
        "<leader>t",
        function()
          local dir = vim.fn.fnameescape(current_buffer_dir())
          vim.cmd("ToggleTerm direction=float dir=" .. dir)
        end,
        desc = "Toggle terminal",
      },
    },
    opts = {
      direction = "float",
      autochdir = true,
      float_opts = {
        border = "curved",
        winblend = 3,
      },
    },
  },
}
