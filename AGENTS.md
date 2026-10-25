# AGENTS.md

macOS-only zsh (Oh My Zsh), tmux, nvim (NvChad) and Ghostty config. Start with `README.md`.

- Language support (Java, Python, Go): follow `LANGUAGES.md`; edit the `[JAVA]`/`[PYTHON]`/`[GO]` markers in `nvim/lua/configs/`.
- Machine state: run `./doctor.sh` before and after a change.
- Each machine keeps its own git and gh setup; leave `~/.gitconfig` and `gh auth` as they are.
- Work machines are pull-only: put machine-specific changes in `~/.zshrc.local`, `nvim/lua/local.lua`, `~/.tmux.local.conf` or `~/.config/ghostty/local`.
- Scripts must run on stock macOS bash 3.2 (a new machine has no newer bash): expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}`.
- Checks: `test/lint.sh` (fast) and `test/fresh-home.sh` (full install in a temp HOME; use `FAST=1` for fast iteration); CI runs both on macOS.
- Contributing / PRs: if not repository owner, create a fork (`gh repo fork --remote=true`) and push branch to origin fork.
