local treesitter_languages = {
  "bash",
  "c",
  "cpp",
  "css",
  "fish",
  "haskell",
  "html",
  "hyprlang",
  "javascript",
  "json",
  "lua",
  "make",
  "markdown",
  "markdown_inline",
  "python",
  "regex",
  "sql",
  "toml",
  "typescript",
  "vim",
}

local parser_install_dir = vim.fn.stdpath("data") .. "/site"

local function has_c_compiler()
  local compilers = { "cc", "gcc", "clang", "cl", "zig" }
  for _, compiler in ipairs(compilers) do
    if vim.fn.executable(compiler) == 1 then
      return true
    end
  end
  return false
end

local treesitter_textobjects = {
  select = {
    enable = true,
    lookahead = true,
    keymaps = {
      ["af"] = "@function.outer",
      ["if"] = "@function.inner",
      ["ac"] = "@class.outer",
      ["ic"] = "@class.inner",
    },
  },
  move = {
    enable = true,
    set_jumps = true,
    goto_next_start = {
      ["]m"] = "@function.outer",
      ["]]"] = "@class.outer",
    },
    goto_previous_start = {
      ["[m"] = "@function.outer",
      ["[["] = "@class.outer",
    },
  },
}

local function setup_legacy_treesitter()
  local ok, configs = pcall(require, "nvim-treesitter.configs")
  if not ok then
    return false
  end

  local compiler_available = has_c_compiler()
  vim.opt.runtimepath:prepend(parser_install_dir)

  configs.setup({
    ensure_installed = compiler_available and treesitter_languages or {},
    auto_install = false,
    parser_install_dir = parser_install_dir,
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = false,
    },
    indent = {
      enable = true,
    },
    textobjects = treesitter_textobjects,
  })

  return true
end

local function setup_modern_treesitter()
  if vim.fn.has("nvim-0.12") == 0 then
    return false
  end

  local ok, treesitter = pcall(require, "nvim-treesitter")
  if not ok or type(treesitter.setup) ~= "function" then
    return false
  end

  vim.opt.runtimepath:prepend(parser_install_dir)

  treesitter.setup({
    install_dir = parser_install_dir,
  })

  return true
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    lazy = false,
    build = ":TSUpdate",
    dependencies = {
      {
        "nvim-treesitter/nvim-treesitter-textobjects",
        branch = "master",
      },
    },
    config = function()
      if setup_legacy_treesitter() or setup_modern_treesitter() then
        return
      end

      vim.schedule(function()
        vim.notify_once(
          "Skipped nvim-treesitter setup. Run :Lazy restore to use the pinned master branch on Neovim 0.11.",
          vim.log.levels.WARN
        )
      end)
    end,
  },
  {
    "iamcco/markdown-preview.nvim",
    ft = { "markdown" },
    cmd = {
      "MarkdownPreview",
      "MarkdownPreviewStop",
      "MarkdownPreviewToggle",
    },
    build = ":call mkdp#util#install()",
    init = function()
      vim.g.mkdp_auto_start = 0
      vim.g.mkdp_auto_close = 1
      vim.g.mkdp_refresh_slow = 0
      vim.g.mkdp_command_for_global = 0
      vim.g.mkdp_open_to_the_world = 0
      vim.g.mkdp_browser = ""
      vim.g.mkdp_echo_preview_url = 1
    end,
    keys = {
      { "<leader>mp", "<cmd>MarkdownPreview<cr>", desc = "Markdown preview" },
      { "<leader>ms", "<cmd>MarkdownPreviewStop<cr>", desc = "Markdown preview stop" },
    },
  },
  {
    "lervag/vimtex",
    lazy = false,
    init = function()
      vim.g.vimtex_quickfix_enabled = 0
      vim.g.vimtex_quickfix_mode = 0
      vim.g.vimtex_quickfix_open_on_warning = 0
      vim.g.vimtex_compiler_silent = 1
      vim.g.vimtex_view_forward_search_on_start = 1
      vim.g.vimtex_view_method = "zathura"
      vim.g.vimtex_compiler_method = "latexmk"
      vim.g.vimtex_compiler_latexmk = {
        build_dir = "build",
        callback = 1,
        continuous = 1,
        executable = "latexmk",
        hooks = {},
        options = {
          "-verbose",
          "-file-line-error",
          "-synctex=1",
          "-interaction=nonstopmode",
          "-shell-escape",
        },
      }
      vim.g.vimtex_compiler_latexmk_engines = {
        ["_"] = "-pdf",
        ["pdflatex"] = "-pdf",
        ["xelatex"] = "-xelatex",
        ["lualatex"] = "-lualatex",
      }
      vim.g.vimtex_complete_enabled = 1
      vim.g.vimtex_imaps_enabled = 0
    end,
  },
  {
    "kawre/leetcode.nvim",
    cmd = "Leet",
    build = ":TSUpdate html",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-tree/nvim-web-devicons",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {
      lang = "cpp",
      logging = true,
      console = {
        open_on_runcode = true,
        size = {
          width = "90%",
          height = "75%",
        },
      },
      description = {
        position = "left",
        width = "40%",
        show_stats = true,
      },
    },
  },
}
