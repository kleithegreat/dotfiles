require'nvim-treesitter.configs'.setup {
    -- A list of parser names, or "all"
    ensure_installed = { "c", "lua", "vim", "help", "bash", "comment", "cpp", "dockerfile", "fish", "gitignore", "html", "http", "java", "javascript", "json", "json5", "jsonc", "latex", "lua", "markdown", "python", "rasi", "ruby", "rust", "sql", "swift", "sxhkdrc", "terraform", "toml", "yaml" },

    -- Install parsers synchronously (only applied to 'ensure_installed')
    sync_install = false,
    auto_install = true,
    highlight = {
        enable = true,
    },
}
