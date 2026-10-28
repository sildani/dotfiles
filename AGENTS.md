# AGENTS.md

macOS-only zsh (Oh My Zsh), tmux, nvim (NvChad) and Ghostty config. Start with `README.md`.

- Language support (Java, Python, Go): follow `LANGUAGES.md`; edit the `[JAVA]`/`[PYTHON]`/`[GO]` markers in `nvim/lua/configs/`.
- Machine state: run `./doctor.sh` before and after a change.
- Each machine keeps its own git and gh setup; leave `~/.gitconfig` and `gh auth` as they are.
- Work machines are pull-only: put machine-specific changes in `~/.zshrc.local`, `nvim/lua/local.lua`, `~/.tmux.local.conf` or `~/.config/ghostty/local`.
- Optional per-machine tweaks: `<tool>/extras/`, turned on from that tool's per-machine file (README "Optional extras").
- Scripts must run on stock macOS bash 3.2 (a new machine has no newer bash): expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}`.
- Checks: `test/lint.sh` (fast), `test/lint-selftest.sh` (after changing lint's marker or extras checks) and `test/fresh-home.sh` (full install in a temp HOME); CI runs all three on macOS. `test/fresh-home.sh` takes minutes: run it once for green, in the background with output to a log, and again after any change to what it installs or checks; docs-only changes skip it.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for sildani/dotfiles, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created only when first needed. See `docs/agents/domain.md`.

### Writing code

Every change reaches `main` through a pull request; `hooks/pre-commit` refuses commits on `main`.

The user runs `/mattpocock-skills:implement` from `main`. Carry it through to a pushed branch in one go:

1. Pull `main` and branch off it, named after the change. `/implement` commits to the current branch.
2. Build with `tdd`, then commit, staging files by name (`code-review` diffs `main...HEAD`).
3. Run `code-review`. Apply the fixes that hold up in a follow-up commit; report the findings left unfixed, with why.
4. Push the branch, report, and stop. When the user runs `/mattpocock-skills:pr`, create the PR (`gh pr create`) with a body that follows that skill.
5. Watch CI by run ID. Green: merge it and run `./prune-merged.sh` (it switches to `main`, pulls, and deletes every merged branch locally and on `origin`). Red: stop and report.
6. Suggest `/mattpocock-skills:retro`; the user runs it.

Several issues in one session: follow `docs/agents/batch.md`.

### Handoffs

`.scratch/` is gitignored local space. `/handoff` writes here, not to `$TMPDIR`:

- Write to `.scratch/handoff/handoff.md`.
- If it already exists, ask: update it in place, or move it to `.scratch/handoff/handoff-<YYYY-MM-DD-HHMM>.md` and write a fresh one.
- When a handoff is done, move it to `.scratch/handoff/archive/<YYYY-MM-DD>-<slug>.md` and add a `Resolved by:` line linking the PRs that closed it, if any.
