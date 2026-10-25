# AGENTS.md

macOS-only zsh (Oh My Zsh), tmux, nvim (NvChad) and Ghostty config. Start with `README.md`.

- Language support (Java, Python, Go): follow `LANGUAGES.md`; edit the `[JAVA]`/`[PYTHON]`/`[GO]` markers in `nvim/lua/configs/`.
- Machine state: run `./doctor.sh` before and after a change.
- Each machine keeps its own git and gh setup; leave `~/.gitconfig` and `gh auth` as they are.
- Work machines are pull-only: put machine-specific changes in `~/.zshrc.local`, `nvim/lua/local.lua`, `~/.tmux.local.conf` or `~/.config/ghostty/local`.
- Optional tweaks that some machines want go in `<tool>/extras/`, off by default; a machine turns one on by sourcing it from that tool's per-machine file. List each one in the README's extras table; install.sh and doctor.sh only point there.
- Scripts must run on stock macOS bash 3.2 (a new machine has no newer bash): expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}`.
- Checks: `test/lint.sh` (fast) and `test/fresh-home.sh` (full install in a temp HOME); CI runs both on macOS.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for sildani/dotfiles, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created only when first needed. See `docs/agents/domain.md`.
