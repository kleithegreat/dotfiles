vim.lsp.enable({ "bend", "copilot", "lua_ls", "nixd", "pyright", "texlab" })
vim.lsp.inline_completion.enable()

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("lsp", {}),
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
    if client:supports_method("textDocument/definition", args.buf) then
      vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = args.buf, desc = "Go to definition" })
    end
  end,
})

require("blink.cmp").setup({
  keymap = {
    preset = "default",
    ["<Tab>"] = {
      "snippet_forward",
      function()
        return vim.lsp.inline_completion.get()
      end,
      "fallback",
    },
  },
  completion = { documentation = { auto_show = true } },
  signature = { enabled = true },
})
