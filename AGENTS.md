# AGENTS.md

macOS-only zsh (Oh My Zsh), tmux, nvim (NvChad) and Ghostty config. Start with `README.md`.

- Language support (Java, Python, Go): follow `LANGUAGES.md`; edit the `[JAVA]`/`[PYTHON]`/`[GO]` markers in `nvim/lua/configs/`.
- Machine state: run `./doctor.sh` before and after a change.
- Each machine keeps its own git and gh setup; leave `~/.gitconfig` and `gh auth` as they are.
- Work machines are pull-only: put machine-specific changes in `~/.zshrc.local`, `nvim/lua/local.lua`, `~/.tmux.local.conf` or `~/.config/ghostty/local`.
- Optional per-machine tweaks: `<tool>/extras/`, turned on from that tool's per-machine file (README "Optional extras").
- Scripts must run on stock macOS bash 3.2 (a new machine has no newer bash): expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}`.
- Checks: `test/lint.sh` (fast), `test/lint-selftest.sh` (after changing lint's marker or extras checks) and `test/fresh-home.sh` (full install in a temp HOME); CI runs all three on macOS.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for sildani/dotfiles, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created only when first needed. See `docs/agents/domain.md`.

### Writing code

Every change reaches `main` through a pull request; `hooks/pre-commit` refuses commits on `main`.

By default, suggest this flow before starting:

1. Branch off `main`. `/implement` commits to the current branch, so branch first.
2. The user runs `/mattpocock-skills:implement`, which builds with `tdd` and ends with `code-review`. It is user-invoked only, so suggest it rather than call it. Commit, staging files by name, before its `code-review` (it diffs `main...HEAD`); fixes go in a follow-up commit.
3. Push, and open a PR whose body follows the `mattpocock-skills:pr` skill.
4. Watch CI; if it passes, merge the PR. If it fails, stop and report.
5. Run `./prune-merged.sh`: it switches to `main`, pulls, and deletes every merged branch locally and on `origin`.
6. The user runs `/mattpocock-skills:retro`. It is user-invoked only, so suggest it rather than call it.

Several issues in one session: follow `docs/agents/batch.md`.

### Handoffs

`.scratch/` is gitignored local space. `/handoff` writes here, not to `$TMPDIR`:

- Write to `.scratch/handoff/handoff.md`.
- If it already exists, ask: update it in place, or move it to `.scratch/handoff/handoff-<YYYY-MM-DD-HHMM>.md` and write a fresh one.
- When a handoff is done, move it to `.scratch/handoff/archive/<YYYY-MM-DD>-<slug>.md` and add a `Resolved by:` line linking the PRs that closed it, if any.
