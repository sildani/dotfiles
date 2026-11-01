-- What update.sh runs headless. A plain +lua error or a failed plugin doesn't
-- change nvim's exit code, so each failure quits with 1 here.
local M = {}

local function quit_failed()
  vim.cmd "1cquit"
end

-- Every plugin but those named in $SKIP_PLUGINS, space-separated.
function M.plugins()
  local lazy = require "lazy"
  local skip = vim.split(vim.env.SKIP_PLUGINS or "", " ")
  local plugins = vim.tbl_filter(function(plugin)
    return not vim.list_contains(skip, plugin.name)
  end, lazy.plugins())
  if not pcall(lazy.update, { wait = true, show = false, plugins = plugins }) then
    quit_failed()
  end
  for _, plugin in ipairs(plugins) do
    if require("lazy.core.plugin").has_errors(plugin) then
      quit_failed()
    end
  end
end

function M.parsers()
  require("lazy").load { plugins = { "nvim-treesitter" } }
  local ok, updated = pcall(function()
    return require("nvim-treesitter").update():wait(300000)
  end)
  if not (ok and updated) then
    quit_failed()
  end
end

return M
