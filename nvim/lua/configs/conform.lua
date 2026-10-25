local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    -- css = { "prettier" },
    -- html = { "prettier" },

    -- [JAVA] uncomment after :MasonInstall google-java-format (optional, see LANGUAGES.md#java)
    -- java = { "google-java-format" },

    -- [PYTHON] uncomment after :MasonInstall ruff (see LANGUAGES.md#python)
    -- python = { "ruff_organize_imports", "ruff_format" },

    -- [GO] uncomment after :MasonInstall goimports gofumpt (see LANGUAGES.md#go)
    -- go = { "goimports", "gofumpt" },
  },

  -- format_on_save = {
  --   -- These options will be passed to conform.format()
  --   timeout_ms = 500,
  --   lsp_fallback = true,
  -- },
}

return options
