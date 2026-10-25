-- Treesitter parsers installed by install.sh and :TSInstallAll.
--
-- The platform list covers the files in the dotfiles repo itself. Language
-- parsers are added by hand when you set a language up: see LANGUAGES.md.
return {
  ensure_installed = {
    -- platform (NvChad defaults + dotfiles repo files)
    "lua",
    "luadoc",
    "printf",
    "vim",
    "vimdoc",
    "bash",
    "markdown",
    "markdown_inline",
    "json",
    "yaml",
    "toml",

    -- [JAVA] uncomment, then run :TSInstallAll (see LANGUAGES.md#java)
    -- "java",

    -- [PYTHON] uncomment, then run :TSInstallAll (see LANGUAGES.md#python)
    -- "python",

    -- [GO] uncomment, then run :TSInstallAll (see LANGUAGES.md#go)
    -- "go", "gomod", "gosum", "gowork",
  },
}
