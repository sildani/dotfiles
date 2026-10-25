require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

-- move between nvim windows and tmux panes (vim-tmux-navigator)
map("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>", { desc = "switch window/pane left" })
map("n", "<C-j>", "<cmd>TmuxNavigateDown<cr>", { desc = "switch window/pane down" })
map("n", "<C-k>", "<cmd>TmuxNavigateUp<cr>", { desc = "switch window/pane up" })
map("n", "<C-l>", "<cmd>TmuxNavigateRight<cr>", { desc = "switch window/pane right" })
