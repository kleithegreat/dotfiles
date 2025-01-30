-- File: lua/plugins.lua
-- Plugin configurations using lazy.nvim

return {
    -- Color scheme
    {
        "ellisonleao/gruvbox.nvim",
        lazy = false,          -- Load during startup
        priority = 1000,       -- Load before other plugins
        config = function()
            require("gruvbox").setup({
                transparent_mode = false,
            })
            vim.cmd([[colorscheme gruvbox]])
        end,
    },

    -- File explorer
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("nvim-tree").setup()
            vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>')
        end
    },

    -- Fuzzy finder (Telescope)
    {
        'nvim-telescope/telescope.nvim',
        dependencies = { 'nvim-lua/plenary.nvim' },
        config = function()
            local builtin = require('telescope.builtin')
            -- File finding
            vim.keymap.set('n', '<leader>ff', builtin.find_files)
            -- Text search
            vim.keymap.set('n', '<leader>fg', builtin.live_grep)
            -- Buffer management
            vim.keymap.set('n', '<leader>fb', builtin.buffers)
        end
    },

    -- Syntax highlighting and parsing
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        config = function()
            require("nvim-treesitter.configs").setup({
                -- Languages to install
                ensure_installed = { "lua", "vim", "javascript", "python" },
                auto_install = true,
                highlight = { enable = true },
                indent = { enable = true },
            })
        end
    },

    -- LSP Configuration
    {
        'VonHeikemen/lsp-zero.nvim',
        branch = 'v3.x',
        dependencies = {
            -- LSP Support
            'neovim/nvim-lspconfig',
            'williamboman/mason.nvim',
            'williamboman/mason-lspconfig.nvim',
            -- Autocompletion
            'hrsh7th/nvim-cmp',
            'hrsh7th/cmp-buffer',
            'hrsh7th/cmp-path',
            'hrsh7th/cmp-nvim-lsp',
            'hrsh7th/cmp-nvim-lua',
            -- Snippets
            'L3MON4D3/LuaSnip',
        },
        config = function()
            local lsp_zero = require('lsp-zero')
            
            -- Default LSP keybindings
            lsp_zero.on_attach(function(client, bufnr)
                lsp_zero.default_keymaps({buffer = bufnr})
            end)
            
            -- Configure Mason for LSP management
            require('mason').setup({})
            require('mason-lspconfig').setup({
                ensure_installed = {'lua_ls', 'pyright'},
                handlers = {
                    lsp_zero.default_setup,
                },
            })
        end
    },

    -- Debugging support
    {
        "mfussenegger/nvim-dap",
        dependencies = {
            "rcarriga/nvim-dap-ui",
            "mfussenegger/nvim-dap-python",
        }
    },

    -- Enhanced syntax highlighting
    {
        "nvim-treesitter/nvim-treesitter-textobjects",
    },

    -- Code formatting
    {
        "mhartington/formatter.nvim",
    },

    -- Buffer line (tabs)
    {
        'akinsho/bufferline.nvim',
        version = "*",
        dependencies = 'nvim-tree/nvim-web-devicons',
        config = function()
            require("bufferline").setup({
                options = {
                    diagnostics = "nvim_lsp",
                    separator_style = "slant"
                }
            })
        end
    }
}