require("mason").setup()
require("mason-lspconfig").setup({
  ensure_installed = {
    "lua_ls",
    "clangd",
    "jdtls",
    "marksman",
    "rust_analyzer",
    "taplo",
    "yamlls",
    "ansiblels",
    "bashls",
    "jsonls",
    "html",
    "cssls",
    "quick_lint_js",
    "terraformls",
    "ltex",
  }
})

local on_attach = function(_, _)
  vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, {})
  vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, {})

  vim.keymap.set('n', 'gd', vim.lsp.buf.definition, {})
  vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, {})
  vim.keymap.set('n', 'gr', require('telescope.builtin').lsp_references, {})
  vim.keymap.set('n', 'K', vim.lsp.buf.hover, {})
end

local capabilities = require('cmp_nvim_lsp').default_capabilities()

require("lspconfig").lua_ls.setup {
  capabilities = capabilities,
}
require("lspconfig").clangd.setup {
  capabilities = capabilities,
}
require("lspconfig").jdtls.setup {
  capabilities = capabilities,
}
require("lspconfig").marksman.setup {
  capabilities = capabilities,
}
require("lspconfig").rust_analyzer.setup {
  capabilities = capabilities,
}
require("lspconfig").taplo.setup {
  capabilities = capabilities,
}
require("lspconfig").yamlls.setup {
  capabilities = capabilities,
}
require("lspconfig").ansiblels.setup {
  capabilities = capabilities,
}
require("lspconfig").bashls.setup {
  capabilities = capabilities,
}
require("lspconfig").jsonls.setup {
  capabilities = capabilities,
}
require("lspconfig").html.setup {
  capabilities = capabilities,
}
require("lspconfig").cssls.setup {
  capabilities = capabilities,
}
require("lspconfig").quick_lint_js.setup {
  capabilities = capabilities,
}
require("lspconfig").terraformls.setup {
  capabilities = capabilities,
}
require("lspconfig").ltex.setup {
  capabilities = capabilities,
}
