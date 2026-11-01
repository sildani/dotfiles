# AGENTS.md

macOS-only zsh (Oh My Zsh), tmux, nvim (NvChad) and Ghostty config. Start with `README.md`.

- Language support (Java, Python, Go): follow `LANGUAGES.md`; edit the `[JAVA]`/`[PYTHON]`/`[GO]` markers in `nvim/lua/configs/`.
- Machine state: run `./doctor.sh` before and after a change to it; docs-only changes skip it.
- Each machine keeps its own git and gh setup; leave `~/.gitconfig` and `gh auth` as they are.
- Any Mac can commit shared changes. Put changes for one Mac in `~/.zshrc.local`, `nvim/lua/local.lua`, `~/.tmux.local.conf` or `~/.config/ghostty/local`.
- Optional per-machine tweaks: `<tool>/extras/`, turned on from that tool's per-machine file (README "Optional extras").
- Scripts must run on stock macOS bash 3.2 (a new machine has no newer bash): expand possibly-empty arrays as `${arr[@]+"${arr[@]}"}`.
- Checks: `test/lint.sh` (fast), `test/lint-selftest.sh` (after changing lint's marker, extras or guard checks; takes minutes, so give the call a 5-minute timeout), `test/doctor-warnings.sh` (`doctor.sh` warnings, in seconds), `test/updates.sh` (`update.sh` and the reminder against fakes, in seconds) and `test/fresh-home.sh` (full install in a temp HOME); CI runs all five on macOS. `test/fresh-home.sh` takes minutes: run it in the background as `test/fresh-home.sh > "$log" 2>&1; rc=$?; tail -5 "$log"; exit $rc` with `log` set to a file in your scratchpad, so the notification carries the test's exit code, and leave the repo alone until it finishes. Run it again after any change to what it installs or checks; docs-only changes skip it.

## Agent skills

### Issue tracker

Issues live in GitHub Issues for sildani/dotfiles, via the `gh` CLI. See `docs/agents/issue-tracker.md`, also when writing an agent brief.

### Triage labels

Default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root, created only when first needed. See `docs/agents/domain.md`.

### Writing code

Every change reaches `main` through a pull request; `hooks/pre-commit` refuses commits on `main`.

The user runs `/mattpocock-skills:implement` from `main`. Carry it through to a pushed branch in one go:

1. Pull `main` and branch off it, named after the change. `/implement` commits to the current branch.
2. Build with `tdd`, picking the seams yourself and naming them in the report, then commit, staging files by name (`code-review` diffs `main...HEAD`).
3. Once `git log` shows the commit, run `code-review`. Apply the fixes that hold up in a follow-up commit; report the findings left unfixed, with why. Docs-only edits the user approved verbatim skip `code-review`. Then run `test/fresh-home.sh` once for green.
4. Push the branch, report, and stop. When the user runs `/mattpocock-skills:pr`, create the PR (`gh pr create`) with a body that follows that skill.
5. Watch CI by run ID. Green: run `gh pr merge --merge --match-head-commit <full-sha>` with the commit CI passed, then `./prune-merged.sh` (it switches to `main`, pulls, and deletes every merged branch locally and on `origin`), then report. Red: stop and report.
6. With no tasks left in the session, suggest `/mattpocock-skills:retro`; the user runs it.

Several issues in one session: follow `docs/agents/batch.md`.

### Handoffs

`.scratch/` is gitignored local space. `/handoff` writes here, not to `$TMPDIR`:

- Write to `.scratch/handoffs/handoff.md`.
- If it already exists, ask: update it in place, or move it to `.scratch/handoffs/handoff-<YYYY-MM-DD-HHMM>.md` and write a fresh one.
- When you pick up a handoff, its `Next:` heading names a command the user types, such as `/mattpocock-skills:triage <n>`. These user-only skills are installed but left out of your skill list, so ask the user to run it.
- When a handoff is done, move it to `.scratch/handoffs/archive/<YYYY-MM-DD>-<slug>.md` and add a `Resolved by:` line linking the PRs that closed it, if any.
