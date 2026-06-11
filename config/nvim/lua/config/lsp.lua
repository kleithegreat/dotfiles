local M = {}

local function map(bufnr, mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, {
    buffer = bufnr,
    silent = true,
    desc = desc,
  })
end

local function capabilities()
  local base = vim.lsp.protocol.make_client_capabilities()
  local ok, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
  if ok then
    return cmp_nvim_lsp.default_capabilities(base)
  end
  return base
end

local function on_attach(args)
  local client = vim.lsp.get_client_by_id(args.data.client_id)
  local bufnr = args.buf

  map(bufnr, "n", "gd", vim.lsp.buf.definition, "Go to definition")
  map(bufnr, "n", "gD", vim.lsp.buf.declaration, "Go to declaration")
  map(bufnr, "n", "gi", vim.lsp.buf.implementation, "Go to implementation")
  map(bufnr, "n", "gr", vim.lsp.buf.references, "List references")
  map(bufnr, "n", "K", vim.lsp.buf.hover, "Hover")
  map(bufnr, "n", "<C-k>", vim.lsp.buf.signature_help, "Signature help")
  map(bufnr, "n", "<leader>D", vim.lsp.buf.type_definition, "Type definition")
  map(bufnr, "n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
  map(bufnr, "n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
  map(bufnr, "n", "gl", vim.diagnostic.open_float, "Line diagnostics")
  map(bufnr, "n", "[d", function()
    vim.diagnostic.jump({ count = -1, float = true })
  end, "Previous diagnostic")
  map(bufnr, "n", "]d", function()
    vim.diagnostic.jump({ count = 1, float = true })
  end, "Next diagnostic")

  if client and client:supports_method("textDocument/documentSymbol", bufnr) then
    local ok, navic = pcall(require, "nvim-navic")
    if ok then
      navic.attach(client, bufnr)
    end
  end
end

function M.setup()
  vim.diagnostic.config({
    severity_sort = true,
    float = {
      border = "rounded",
      source = "if_many",
    },
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
    callback = on_attach,
  })

  local server_capabilities = capabilities()

  vim.lsp.config("lua_ls", {
    capabilities = server_capabilities,
    settings = {
      Lua = {
        diagnostics = {
          globals = { "vim" },
        },
        workspace = {
          checkThirdParty = false,
        },
      },
    },
  })

  vim.lsp.config("pyright", {
    capabilities = server_capabilities,
  })

  vim.lsp.config("texlab", {
    capabilities = server_capabilities,
  })

  vim.lsp.config("ltex", {
    capabilities = server_capabilities,
    filetypes = { "markdown", "tex", "plaintex" },
    settings = {
      ltex = {
        checkFrequency = "save",
        enabled = { "spelling" },
        disabledRules = {
          ["en-US"] = { "GRAMMAR", "STYLE", "TYPOGRAPHY" },
        },
      },
    },
  })

  vim.lsp.enable("lua_ls")
  vim.lsp.enable("pyright")
  vim.lsp.enable("texlab")
  vim.lsp.enable("ltex")
end

return M
