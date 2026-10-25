# Language support (manual on purpose)

`install.sh` sets up the editor platform only. Language support is added by
hand, per machine, when you actually need it. Each language takes three edits in
`nvim/lua/configs/`, all marked with a `[JAVA]` / `[PYTHON]` / `[GO]` comment:

| File             | What you uncomment                          |
| ---------------- | ------------------------------------------- |
| `treesitter.lua` | the parser(s), for syntax highlighting      |
| `lspconfig.lua`  | the language server(s)                      |
| `conform.lua`    | the formatter(s)                            |

Find them all with: `rg -n '\[JAVA\]|\[PYTHON\]|\[GO\]' ~/code/dotfiles/nvim`

These files live in the repo, so uncommenting is a repo change. On a work
machine (pull-only), either make the change on the personal laptop and
`git pull`, or put machine-only setup in `nvim/lua/local.lua` (git-ignored):

```lua
-- nvim/lua/local.lua: e.g. Go only on this machine
vim.lsp.enable { "gopls" }
require("conform").formatters_by_ft.go = { "goimports", "gofumpt" }
```

(Parsers can be installed ad hoc with `:TSInstall go`; they persist without
being in the list.)

Run `./doctor.sh` before and after: the **Languages** section tells you what is
missing, and when it says `set up` you're done.

General tools you'll use in every recipe:

- `:Mason`: browse and install language servers and formatters (`:MasonInstall <name>`)
- `:TSInstallAll`: installs every parser in `treesitter.lua`
- `:checkhealth vim.lsp`: which servers are attached to the current buffer
- `:ConformInfo`: which formatters apply to the current buffer
- `<leader>fm` (space f m): format the buffer (NvChad mapping)

---

## Java

**Needs:** a JDK 21+ to *run* jdtls (your projects can still target older Java).
Check with `/usr/libexec/java_home -V`. If your company ships its own JDK, use
that; otherwise `brew install --cask temurin@21`.

1. `treesitter.lua`: uncomment `"java"`, then `:TSInstallAll`
2. `:MasonInstall jdtls`
3. `lspconfig.lua`: uncomment `"jdtls"`
4. Optional formatter: `:MasonInstall google-java-format` and uncomment the
   `java` line in `conform.lua`. Skip it if your team formats with a
   Gradle/Maven plugin (spotless etc.), and use that instead.

**Check:** open a `.java` file inside a Maven/Gradle project. The first start
indexes the project and takes a while. `:checkhealth vim.lsp` should list
`jdtls`; `gd` on a class should jump to it.

**If you outgrow it:** plain lspconfig gives you completion, diagnostics and
navigation. For debugging, test running and better multi-module support,
switch to the [`nvim-jdtls`](https://github.com/mfussenegger/nvim-jdtls)
plugin (and drop `"jdtls"` from `lspconfig.lua` so they don't both start).

## Python

**Needs:** `python3` and `node` (basedpyright is a Node program). Check with
`python3 --version && node --version`; install with `brew install python node`.

1. `treesitter.lua`: uncomment `"python"`, then `:TSInstallAll`
2. `:MasonInstall basedpyright ruff`
3. `lspconfig.lua`: uncomment `"basedpyright"` and `"ruff"`
   (basedpyright = types/navigation, ruff = lint diagnostics)
4. `conform.lua`: uncomment the `python` line (ruff sorts imports + formats)

**Check:** open a `.py` file. `:checkhealth vim.lsp` should list both servers.
For a project virtualenv, start nvim with the venv activated (`source
.venv/bin/activate && nvim`) so imports resolve.

## Go

**Needs:** `go` (Mason builds gopls and the formatters with it). Check with
`go version`; install with `brew install go`.

1. `treesitter.lua`: uncomment `"go", "gomod", "gosum", "gowork"`, then `:TSInstallAll`
2. `:MasonInstall gopls goimports gofumpt`
3. `lspconfig.lua`: uncomment `"gopls"`
4. `conform.lua`: uncomment the `go` line

**Check:** open a `.go` file inside a module (a directory with `go.mod`).
`:checkhealth vim.lsp` should list `gopls`; `<leader>fm` should fix imports.

---

## When doctor says "partly set up"

It lists exactly what's still missing, e.g.
`still to do: :MasonInstall ruff; enable "basedpyright" in lspconfig.lua`.
Do those, restart nvim, and re-run `./doctor.sh`.
