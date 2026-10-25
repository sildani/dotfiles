# Coding standards

Judgement calls for reviewing changes to this repo. `test/lint.sh` enforces the mechanical rules
(shellcheck, zsh syntax, secrets, docs listing every link and override file, language recipes),
so they aren't repeated here.

## Tests stay inside their temp HOME

`test/fresh-home.sh` may read from the real HOME (it links the Hurmit font in), but nothing it
sets up lets `install.sh`, a plugin manager or nvim write there. A symlink from the temp HOME to a
real plugin, data or config directory breaks this: the install writes through it into the real
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

## Messages the tests match are marked

A script message that `test/fresh-home.sh` greps for carries a `# fresh-home.sh greps for "<text>"`
comment on its line, as in `install.sh`, so whoever rewords it updates the test too. A new grep in
the test adds the marker to the message it matches.

## One change per PR, described as it is

A PR's description matches its diff: each behaviour it claims is in the code, and each change in
the diff is in the description. Unrelated changes (a tmux binding in a zsh PR) go in their own PR.
Revert and blast-radius claims cover every machine that pulls and re-runs `install.sh`.
