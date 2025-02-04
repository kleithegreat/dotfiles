-- File: lua/plugins.lua
-- Complete plugin configuration using lazy.nvim package manager
-- Each plugin is defined in a table with its configuration

return {
    -- Theme/Colorscheme
    {
        "ellisonleao/gruvbox.nvim",
        lazy = false,          -- Load during startup (not lazy-loaded)
        priority = 1000,       -- High priority ensures theme loads before other plugins
        config = function()
            require("gruvbox").setup({
                transparent_mode = false,  -- Set to true if you want a transparent background
            })
            vim.cmd([[colorscheme gruvbox]])  -- Actually set the colorscheme
        end,
    },

    -- Markdown Preview Plugin
    {
        "iamcco/markdown-preview.nvim",
        event = "VeryLazy",
        build = ":call mkdp#util#install()",
        config = function()
            -- Default settings for markdown preview
            vim.g.mkdp_auto_start = 0          -- Don't auto-start preview
            vim.g.mkdp_auto_close = 1          -- Auto-close preview when changing buffers
            vim.g.mkdp_refresh_slow = 0        -- Fast refresh on content changes
            vim.g.mkdp_command_for_global = 0  -- Only enable for markdown files
            vim.g.mkdp_open_to_the_world = 0   -- Only preview locally
            vim.g.mkdp_browser = ''            -- Use default browser
            vim.g.mkdp_echo_preview_url = 1    -- Show preview URL in command line
            
            -- Set custom keymaps for markdown preview
            vim.keymap.set('n', '<leader>mp', ':MarkdownPreview<CR>', 
                { desc = 'Start markdown preview' })
            vim.keymap.set('n', '<leader>ms', ':MarkdownPreviewStop<CR>', 
                { desc = 'Stop markdown preview' })
        end,
    },

    -- File Explorer (like VS Code's sidebar)
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },  -- Icons for the file tree
        config = function()
            require("nvim-tree").setup()
            -- Toggle file explorer with Space + e
            vim.keymap.set('n', '<leader>e', ':NvimTreeToggle<CR>')
        end
    },

    -- Fuzzy Finder (for searching files, text, etc.)
    {
        'nvim-telescope/telescope.nvim',
        dependencies = { 'nvim-lua/plenary.nvim' },  -- Required dependency for Telescope
        config = function()
            local telescope = require('telescope')
            local builtin = require('telescope.builtin')
            local actions = require('telescope.actions')
            local action_state = require('telescope.actions.state')
    
            telescope.setup({
                defaults = {
                    mappings = {
                        i = {
                            ["<CR>"] = function(prompt_bufnr)
                                local selection = action_state.get_selected_entry()
                                if selection == nil then
                                    return
                                end
                                
                                local filename = selection.value
                                -- Check if file is a PDF
                                if string.match(filename, "%.pdf$") then
                                    -- Close Telescope window
                                    actions.close(prompt_bufnr)
                                    -- Open PDF in Zathura
                                    vim.fn.jobstart({"zathura", filename}, {detach = true})
                                else
                                    -- Use default file opening behavior for non-PDFs
                                    actions.file_edit(prompt_bufnr)
                                end
                            end,
                        }
                    }
                }
            })
    
            -- Keymaps for different telescope functions:
            vim.keymap.set('n', '<leader>ff', builtin.find_files)    -- Space + ff to find files
            vim.keymap.set('n', '<leader>fg', builtin.live_grep)     -- Space + fg to search text
            vim.keymap.set('n', '<leader>fb', builtin.buffers)       -- Space + fb to find buffers
        end
    },

    -- Enhanced syntax highlighting
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",  -- Updates the parsers when the plugin updates
        config = function()
            require("nvim-treesitter.configs").setup({
                ensure_installed = { 
                    "lua",
                    "vim",
                    "c",
                    "cpp",
                    "java",
                    "html",
                    "css",
                    "hyprlang",
                    "bash",
                    "fish",
                    "haskell",
                    "json",
                    "make",
                    "regex",
                    "sql",
                    "toml",
                    "javascript",
                    "typescript",
                    "python",
                    "markdown",
                    "markdown_inline"
                },
                auto_install = false,
                highlight = {
                    enable = true,
                    -- additional_vim_regex_highlighting = { "markdown" },
                    additional_vim_regex_highlighting = false,
                },
                indent = { enable = true },
            })
        end
    },

    -- LSP (Language Server Protocol) Configuration
    {
        'VonHeikemen/lsp-zero.nvim',
        branch = 'v3.x',
        dependencies = {
            -- LSP Support
            'neovim/nvim-lspconfig',           -- Required LSP configuration
            'williamboman/mason.nvim',         -- Package manager for LSP servers
            'williamboman/mason-lspconfig.nvim', -- Bridge between Mason and LSP config
            -- Autocompletion plugins
            'hrsh7th/nvim-cmp',               -- The completion engine
            'hrsh7th/cmp-buffer',             -- Complete words from current buffer
            'hrsh7th/cmp-path',               -- Complete file paths
            'hrsh7th/cmp-nvim-lsp',           -- Complete using LSP
            'hrsh7th/cmp-nvim-lua',           -- Complete Neovim's Lua API
            -- Snippet engine
            'L3MON4D3/LuaSnip',               -- Snippet engine
        },
        config = function()
            local lsp_zero = require('lsp-zero')
            
            -- Setup default LSP keybindings
            lsp_zero.on_attach(function(client, bufnr)
                lsp_zero.default_keymaps({buffer = bufnr})
            end)
            
            -- Configure Mason and install basic language servers
            require('mason').setup({})
            -- In your lsp-zero config section
            require('mason-lspconfig').setup({
                ensure_installed = {'lua_ls', 'pyright', 'texlab', 'ltex'},
                handlers = {
                    lsp_zero.default_setup,
                    -- Add custom setup for ltex
                    ['ltex'] = function()
                        require('lspconfig').ltex.setup({
                            settings = {
                                ltex = {
                                    -- Disable grammar checking
                                    checkFrequency = "save", -- only check on save
                                    enabled = {"spelling"},  -- only enable spell checking
                                    disabledRules = {
                                        ["en-US"] = {"GRAMMAR", "STYLE", "TYPOGRAPHY"}, -- disable grammar/style rules
                                    },
                                }
                            },
                            -- Only enable for specific file types
                            filetypes = { "markdown", "tex", "latex" }
                        })
                    end
                }
            })

            local cmp = require('cmp')
            local cmp_select = {behavior = cmp.SelectBehavior.Select}

            cmp.setup({
                sources = {
                    {name = 'copilot'},
                    {name = 'nvim_lsp'},
                    {name = 'buffer'},
                    {name = 'path'},
                    {name = 'luasnip'},
                },
                mapping = {
                    ['<C-p>'] = cmp.mapping.select_prev_item(cmp_select),
                    ['<C-n>'] = cmp.mapping.select_next_item(cmp_select),
                    ['<C-y>'] = cmp.mapping.confirm({ select = true }),
                    ['<CR>'] = cmp.mapping.confirm({ select = true }),
                }
            })
        end
    },

    -- Github Copilot
    {
        "zbirenbaum/copilot.lua",
        cmd = "Copilot",
        event = "InsertEnter",
        config = function()
            require("copilot").setup({
                filetypes = {
                    markdown = true,
                    ["."] = true,
                },
                suggestion = {
                    enabled = true,
                    auto_trigger = true,
                    keymap = {
                        accept = "<Tab>",
                        accept_word = "<C-l>",
                        next = "<M-]>",
                        prev = "<M-[>",
                        dismiss = "<C-]>",
                    },
                },
                panel = { enabled = false },
            })
        end,
    },

    {
        "zbirenbaum/copilot-cmp",
        dependencies = { "zbirenbaum/copilot.lua" },
        config = function()
            require("copilot_cmp").setup()
        end
    },

    -- LaTeX Support with Enhanced Auto-compilation
    {
        'lervag/vimtex',
        lazy = false,  -- Load at startup
        config = function()
            -- Completely disable quickfix functionality
            vim.g.vimtex_quickfix_enabled = 0
            vim.g.vimtex_quickfix_mode = 0
            vim.g.vimtex_quickfix_open_on_warning = 0
            
            -- Silence compiler messages
            vim.g.vimtex_compiler_silent = 1
            
            -- PDF viewer settings
            vim.g.vimtex_view_forward_search_on_start = 1
            vim.g.vimtex_view_method = 'zathura'
            
            
            -- Enhanced compiler settings with continuous mode
            vim.g.vimtex_compiler_method = 'latexmk'
            vim.g.vimtex_compiler_latexmk = {
                build_dir = 'build',
                callback = 1,
                continuous = 1,
                executable = 'latexmk',
                hooks = {},
                options = {
                    '-verbose',
                    '-file-line-error',
                    '-synctex=1',
                    '-interaction=nonstopmode',
                    '-shell-escape',
                },
            }
            
            -- Compiler engine settings
            vim.g.vimtex_compiler_latexmk_engines = {
                ['_'] = '-pdf',
                ['pdflatex'] = '-pdf',
                ['xelatex'] = '-xelatex',
                ['lualatex'] = '-lualatex',
            }
            
            -- Enable completion
            vim.g.vimtex_complete_enabled = 1
            
            -- Disable insert mode mappings
            vim.g.vimtex_imaps_enabled = 0
            
            -- Set up autocompilation with TextChanged event
            vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
                pattern = {"*.tex"},
                callback = function()
                    vim.cmd('VimtexCompile')
                end,
                group = vim.api.nvim_create_augroup("vimtex_auto_compile", { clear = true })
            })
            
            -- Set up LaTeX-specific settings
            vim.api.nvim_create_autocmd("FileType", {
                pattern = {"tex"},
                callback = function()
                    -- Local settings for LaTeX files
                    vim.opt_local.conceallevel = 2
                    vim.opt_local.spell = true
                    vim.opt_local.spelllang = "en_us"
                end,
                group = vim.api.nvim_create_augroup("vimtex_settings", { clear = true })
            })
        end,
    },

    -- Automatic saving
    {
        'pocco81/auto-save.nvim',
        config = function()
            require('auto-save').setup({
                enabled = true,  -- Enable auto-save
                -- Show a message when auto-save occurs
                execution_message = {
                    message = function()
                        return ("AutoSave: saved at " .. vim.fn.strftime("%H:%M:%S"))
                    end,
                    dim = 0.18,  -- Message opacity
                    cleaning_interval = 1250,
                },
                -- Events that trigger auto-save
                trigger_events = {"InsertLeave", "TextChanged"},  -- Save when leaving insert mode or when text changes
                
                -- Only save if there are actual changes
                condition = function(buf)
                    local fn = vim.fn
                    local utils = require("auto-save.utils.data")
                    if fn.getbufvar(buf, "&modifiable") == 1 and
                        utils.not_in(fn.getbufvar(buf, "&filetype"), {}) then
                        return true
                    end
                    return false
                end,
                write_all_buffers = false,  -- Only save current buffer
                debounce_delay = 135  -- Delay before saving (milliseconds)
            })
        end
    },

    -- Debugging support
    {
        "mfussenegger/nvim-dap",
        dependencies = {
            "rcarriga/nvim-dap-ui",         -- UI for the debugger
            "mfussenegger/nvim-dap-python", -- Python debugging support
        }
    },

    -- Additional syntax objects
    {
        "nvim-treesitter/nvim-treesitter-textobjects",  -- Adds more text objects for selection and manipulation
    },

    -- Code formatting
    {
        "mhartington/formatter.nvim",  -- Provides code formatting capabilities
    },
    
    -- Git signs in the gutter
    {
        'lewis6991/gitsigns.nvim',
        config = function()
            require('gitsigns').setup({
                signs = {
                    add          = { text = '│' },
                    change       = { text = '│' },
                    delete       = { text = '_' },
                    topdelete    = { text = '‾' },
                    changedelete = { text = '~' },
                    untracked    = { text = '┆' },
                },
                current_line_blame = true,  -- Toggle with :Gitsigns toggle_current_line_blame
                current_line_blame_opts = {
                    delay = 300,
                },
                -- Keymaps for navigating hunks
                on_attach = function(bufnr)
                    local gs = package.loaded.gitsigns

                    vim.keymap.set('n', ']c', function()
                        if vim.wo.diff then return ']c' end
                        vim.schedule(function() gs.next_hunk() end)
                        return '<Ignore>'
                    end, {expr=true, buffer = bufnr})

                    vim.keymap.set('n', '[c', function()
                        if vim.wo.diff then return '[c' end
                        vim.schedule(function() gs.prev_hunk() end)
                        return '<Ignore>'
                    end, {expr=true, buffer = bufnr})
                end
            })
        end
    },

    -- Buffer line (tabs at the top of the editor)
    {
        'akinsho/bufferline.nvim',
        version = "*",
        dependencies = 'nvim-tree/nvim-web-devicons',  -- Icons in the buffer line
        config = function()
            require("bufferline").setup({
                options = {
                    diagnostics = "nvim_lsp",  -- Show LSP diagnostics in tabs
                    separator_style = "slant"  -- Slanted separators between tabs
                }
            })
        end
    },

    -- Status line
    {
        'nvim-lualine/lualine.nvim',
        dependencies = { 'nvim-tree/nvim-web-devicons' },
        config = function()
            require('lualine').setup({
                options = {
                    theme = 'gruvbox',
                    component_separators = { left = '', right = ''},
                    section_separators = { left = '', right = ''},
                },
                sections = {
                    lualine_a = {'mode'},
                    lualine_b = {'branch', 'diff', 'diagnostics'},
                    lualine_c = {'filename'},
                    lualine_x = {'encoding', 'fileformat', 'filetype'},
                    lualine_y = {'progress'},
                    lualine_z = {'location'}
                },
                inactive_sections = {
                    lualine_a = {},
                    lualine_b = {},
                    lualine_c = {'filename'},
                    lualine_x = {'location'},
                    lualine_y = {},
                    lualine_z = {}
                },
            })
        end
    },

    {
        'akinsho/toggleterm.nvim',
        version = "*",
        config = function()
            require("toggleterm").setup({
                direction = 'float',  -- Opens in floating window. Use 'horizontal' or 'vertical' if you prefer
                float_opts = {
                    border = 'curved',
                    winblend = 3,
                },
                -- Open terminal in the directory of the current buffer
                auto_cwd = true,
            })
            
            -- Terminal toggle keymap
            vim.keymap.set('n', '<leader>t', function()
                local buf_dir = vim.fn.expand('%:p:h')
                -- Set working directory to current buffer's directory
                vim.cmd('lcd ' .. buf_dir)
                -- Toggle terminal
                vim.cmd('ToggleTerm direction=float')
            end, { desc = 'Toggle terminal in current buffer directory' })
    
            -- Easier way to exit terminal mode
            vim.keymap.set('t', '<Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })
        end
    },

    {
        "kawre/leetcode.nvim",
        build = ":TSUpdate html",    -- Updates TreeSitter HTML parser
        lazy = true,                 -- Load only when explicitly called
        cmd = "Leet",               -- Load when the Leet command is used
        dependencies = {
            "nvim-telescope/telescope.nvim",
            "nvim-lua/plenary.nvim", 
            "MunifTanjim/nui.nvim",
            "nvim-treesitter/nvim-treesitter",
            "nvim-tree/nvim-web-devicons", -- Optional, for file icons
        },
        config = function()
            require("leetcode").setup({
                -- Configuration options
                lang = "cpp", -- Default code editor language
                logging = true, -- Enable logging for debug
                console = {
                    open_on_runcode = true, -- Open console when running code
                    size = {
                        width = "90%",
                        height = "75%",
                    },
                },
                description = {
                    position = "left", -- Show problem description on the left
                    width = "40%", -- Width of description window
                    show_stats = true, -- Show problem stats
                },
            })
        end,
    },

    -- Breadcrumbs
    {
        "utilyre/barbecue.nvim",
        dependencies = {
            "SmiteshP/nvim-navic",
            "nvim-tree/nvim-web-devicons",
        },
        config = function()
            require("barbecue").setup({
                theme = "gruvbox",
                show_modified = true,
                show_dirname = true,
                show_basename = true,
                show_context = true,
            })
        end,
    },

    -- Indent guides
    {
        "lukas-reineke/indent-blankline.nvim",
        main = "ibl",
        config = function()
            require("ibl").setup({
                indent = {
                    char = "│",
                    tab_char = "│",
                },
                scope = { enabled = true },
                exclude = {
                    filetypes = {
                        "help",
                        "alpha",
                        "dashboard",
                        "neo-tree",
                        "Trouble",
                        "trouble",
                        "lazy",
                        "mason",
                        "notify",
                        "toggleterm",
                        "lazyterm",
                    },
                },
            })
        end,
    },

    -- Auto pairs
    {
        "windwp/nvim-autopairs",
        event = "InsertEnter",
        config = function()
            local npairs = require("nvim-autopairs")
            npairs.setup({
                check_ts = true, -- Enable treesitter
                ts_config = {
                    lua = {'string'},-- Don't add pairs in lua string treesitter nodes
                    javascript = {'template_string'}, -- Don't add pairs in javascript template_string
                },
                disable_filetype = { "TelescopePrompt", "spectre_panel" },
                fast_wrap = {
                    map = "<M-e>", -- Alt+e to fast wrap
                    chars = { "{", "[", "(", '"', "'" },
                    pattern = string.gsub([[ [%'%"%)%>%]%)%}%,] ]], "%s+", ""),
                    offset = 0,
                    end_key = "$",
                    keys = "qwertyuiopzxcvbnmasdfghjkl",
                    check_comma = true,
                    highlight = "PmenuSel",
                    highlight_grey = "LineNr",
                },
            })

            -- Make autopairs work with cmp
            local cmp_autopairs = require('nvim-autopairs.completion.cmp')
            local cmp = require('cmp')
            cmp.event:on(
                'confirm_done',
                cmp_autopairs.on_confirm_done()
            )
        end,
    },

    {
        'nvimdev/dashboard-nvim',
        event = 'VimEnter',
        config = function()
            require('dashboard').setup {
                theme = 'hyper',
                disable_move = false,
                shortcut_type = 'letter',
                shuffle_letter = false,
                -- letter_list
                change_to_vcs_root = false,
                config = {
                    header = {
                        'L',
                        'M',
                        'A',
                        'O',
                    },
                    week_header = {
                        enable = true,
                    },
                    shortcut = {},
                    packages = { enable = true },
                    footer = {},
                },
                hide = {
                    statusline = true,
                    -- tabline = true,
                    -- winbar = true,
                },
            }
        end,
        dependencies = { {'nvim-tree/nvim-web-devicons'}}
    },

    -- add multicursor.nvim
}