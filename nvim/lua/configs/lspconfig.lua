require("nvchad.configs.lspconfig").defaults()

local servers = {
  "html",
  "cssls",

  -- [JAVA] uncomment after :MasonInstall jdtls (see LANGUAGES.md#java)
  -- "jdtls",

  -- [PYTHON] uncomment after :MasonInstall basedpyright ruff (see LANGUAGES.md#python)
  -- "basedpyright",
  -- "ruff",

  -- [GO] uncomment after :MasonInstall gopls (see LANGUAGES.md#go)
  -- "gopls",
}
vim.lsp.enable(servers)

-- read :h vim.lsp.config for changing options of lsp servers
