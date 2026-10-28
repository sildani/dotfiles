# Coding standards

Judgement calls for reviewing changes to this repo. `test/lint.sh` enforces the mechanical rules
(shellcheck, zsh syntax, secrets, docs listing every link and override file, language recipes,
the `# fresh-home.sh greps for "<text>"` markers on messages the test matches),
so they aren't repeated here.

Triage's decisions outrank these standards. Read them before calling something a violation: the
issue's comments (`gh issue view <n> --json comments`, with `#n` from the commits) and, in a batch,
`.scratch/handoff/handoff.md`. A diff doing what triage decided isn't a violation; where a decision
looks like it conflicts with a standard, report that as a question for the spec.

## Tests stay inside their temp HOME

`test/fresh-home.sh` may read from the real HOME (it links the Hurmit font in), but nothing it
sets up lets `install.sh`, a plugin manager or nvim write there, or into the real repo's working
tree (the test installs from a copy). A symlink from the temp HOME to a real plugin, data or config
directory, or into the real repo, breaks this: the install writes through it into the real
machine. A test that reuses real state for speed no longer tests a fresh install either.

## A user's existing config is migrated, not just moved

When `install.sh` starts managing a file a machine already has, that machine's setup keeps
working after the install: carry it into the matching per-machine override file (as
`migrate_zshrc` does for `~/.zshrc` → `~/.zshrc.local`), and say in the README how to go back.
A backup alone counts only for files with nothing machine-specific in them. Work machines re-run
`install.sh` after every pull, so a change here reaches every machine.

## Shared configs survive a partial install

A linked config still loads when something it depends on is missing (Oh My Zsh not cloned, a
plugin not installed yet): guard the load and print a one-line hint naming the fix. `install.sh`
orders its steps so that a failure leaves the old config in place rather than a link to a config
that can't load yet.

## Text people read uses the glossary's terms

README text, script messages, comments and PR descriptions use the `GLOSSARY.md` terms
(installer, shared config, per-machine file, extra), not the words it lists under _Avoid_. A new
term goes into the glossary first, then into the text.

## One change per PR, described as it is

A PR's description matches its diff: each behaviour it claims is in the code, and each change in
the diff is in the description. Unrelated changes (a tmux binding in a zsh PR) go in their own PR.
Revert and blast-radius claims cover every machine that pulls and re-runs `install.sh`.
