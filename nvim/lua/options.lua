-- File: lua/options.lua
-- Contains basic Vim options and keymaps

-- General Vim Options
local opt = vim.opt

-- UI Options
opt.number = true         -- Show line numbers
opt.relativenumber = true -- Show relative line numbers
opt.termguicolors = true -- True color support
opt.wrap = false         -- Disable line wrap

-- Indentation
opt.shiftwidth = 2       -- Size of an indent
opt.tabstop = 2          -- Number of spaces tabs count for
opt.expandtab = true     -- Use spaces instead of tabs
opt.smartindent = true   -- Insert indents automatically

-- Search
opt.ignorecase = true    -- Ignore case
opt.smartcase = true     -- Don't ignore case with capitals

-- System
opt.clipboard = "unnamedplus" -- Use system clipboard

-- Keymaps
local keymap = vim.keymap.set

-- Buffer Navigation
keymap('n', '<Tab>', ':bnext<CR>')
keymap('n', '<S-Tab>', ':bprevious<CR>')      -- Shift+Tab
keymap('n', '<leader>bd', ':bd<CR>')          -- Close buffer
keymap('n', '<leader>b', ':buffers<CR>:buffer<Space>')  -- List buffers

-- Window Management
keymap('n', '<leader>sv', ':vsplit<CR>')      -- Split vertically
keymap('n', '<leader>sh', ':split<CR>')       -- Split horizontally

-- Window Resizing
keymap('n', '<C-Up>', ':resize +2<CR>')
keymap('n', '<C-Down>', ':resize -2<CR>')
keymap('n', '<C-Left>', ':vertical resize -2<CR>')
keymap('n', '<C-Right>', ':vertical resize +2<CR>')