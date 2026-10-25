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

  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

  -- Parser list lives in configs/treesitter.lua (platform parsers on, language
  -- parsers commented out until you set a language up; see LANGUAGES.md).
  {
    "nvim-treesitter/nvim-treesitter",
    opts = require "configs.treesitter",
  },
}
