# Coding standards

Judgement calls for reviewing changes to this repo. `test/lint.sh` enforces the mechanical rules
(shellcheck, zsh syntax, secrets, docs listing every link and override file, language recipes,
the `# fresh-home.sh greps for "<text>"` markers on messages the test matches),
so they aren't repeated here.

Triage's decisions outrank these standards. Read them before calling something a violation: the
issue's comments (`gh issue view <n> --json comments`, with `#n` from the commits) and, in a batch,
`.scratch/handoffs/handoff.md`. A diff doing what triage decided isn't a violation; where a decision
looks like it conflicts with a standard, report that as a question for the spec.

## Tests stay inside their temp HOME

`test/fresh-home.sh` may read from the real HOME (it links the Hurmit font in), but nothing it
sets up lets `install.sh`, a plugin manager or nvim write there, or into the real repo's working
tree (the test installs from a copy). A symlink from the temp HOME to a real plugin, data or config
directory, or into the real repo, breaks this: the install writes through it into the real
machine. A test that reuses real state for speed no longer tests a fresh install either.

## A fake proves the script's logic, not the tool's

A fake chooses its own exit codes, so it can't show how the real tool reports failure. A new or
changed check that trusts a tool's exit code or output to detect failure has one real run showing
that signal on a real failure (`nvim --headless "+lua ..." +qa` exits 0 after a Lua error), or the
report or PR says it's unchecked.

## A test that asserts absence is seen failing

A test that asserts something didn't happen (no reminder, no warning, nothing changed) can pass
without reaching the code (`zsh -c true` never reads `~/.zshrc`). The report or PR names a mutation
that made it fail.

A changed test seed has its reason in the report or PR: a new seed can hide the regression the old
one caught.

## A user's existing config is migrated, not just moved

When `install.sh` starts managing a file a machine already has, that machine's setup keeps
working after the install: carry it into the matching per-machine override file (as
`migrate_zshrc` does for `~/.zshrc` → `~/.zshrc.local`), and say in the README how to go back.
A backup alone counts only for files with nothing machine-specific in them. Every machine re-runs
`install.sh` after a pull, so a change here reaches every machine.

## Shared configs survive a partial install

A linked config still loads when something it depends on is missing (Oh My Zsh not cloned, a
plugin not installed yet): guard the load and print a one-line hint naming the fix. `install.sh`
orders its steps so that a failure leaves the old config in place rather than a link to a config
that can't load yet.

## Text people read uses the glossary's terms

README text, script messages, comments and PR descriptions use the `GLOSSARY.md` terms, not the
words it lists under _Avoid_. A new term goes into the glossary first, then into the text.

## Config comments state what was seen

A comment telling people how to use a setting describes behaviour someone saw run. A claim taken
from a tool's docs alone needs a check first, or the PR says it's unchecked.

## One change per PR, described as it is

A PR's description matches its diff: each behaviour it claims is in the code, and each change in
the diff is in the description. Unrelated changes (a tmux binding in a zsh PR) go in their own PR.
Revert and blast-radius claims cover every machine that pulls and re-runs `install.sh`.

## The README describes what `install.sh` does

A change to what the install moves, copies, links or warns about updates the README's description
of it in the same PR, including any by-hand steps that point there. Lint checks the link table;
this covers the prose around it. The installer reads the README, not the script.

## Agent docs follow `writing-for-agents`

`AGENTS.md`, `docs/agents/` and this file are written by the `mattpocock-skills:writing-for-agents` skill's
rules. Each flow or rule lives in one file and the others point to it, so a change to it is a
one-place edit and two files can't give different steps.
