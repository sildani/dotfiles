require "nvchad.autocmds"

-- open nvim-tree when started with a directory (e.g. `nvim .`)
vim.api.nvim_create_autocmd("VimEnter", {
  -- nested so the tree's later :edit into the empty buffer fires BufRead etc.
  nested = true,
  callback = function(data)
    if vim.fn.isdirectory(data.file) ~= 1 then
      return
    end

    vim.cmd.enew()
    vim.cmd.bwipeout(data.buf)
    vim.cmd.cd(data.file)
    require("nvim-tree.api").tree.open()
  end,
})
