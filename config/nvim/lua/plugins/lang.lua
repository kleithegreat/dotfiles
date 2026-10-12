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
      vim.opt.runtimepath:prepend(parser_install_dir)

      require("nvim-treesitter.configs").setup({
        ensure_installed = treesitter_languages,
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
