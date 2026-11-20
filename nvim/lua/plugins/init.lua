return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
    },
  },

  -- Renders markdown in the buffer for reading (raw on the cursor line and in
  -- insert mode). Space m r switches the current buffer between rendered and raw.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = "markdown",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {},
    keys = {
      { "<leader>mr", "<cmd>RenderMarkdown buf_toggle<cr>", ft = "markdown", desc = "markdown toggle render/raw" },
    },
  },

  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

  -- Parser list lives in configs/treesitter.lua (platform parsers on, language
  -- parsers commented out until you set a language up; see LANGUAGES.md).
  {
    "nvim-treesitter/nvim-treesitter",
    opts = require "configs.treesitter",
  },
}
