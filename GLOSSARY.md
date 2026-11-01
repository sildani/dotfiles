# dotfiles

Shared terminal setup (zsh, tmux, nvim, Ghostty) for several macOS machines, any of which can make changes.

## Language

**Installer**:
The person running `install.sh` on a machine. Messages from `install.sh` and the README speak to them.
_Avoid_: user, agent

**Shared config**:
A config file in this repo that `install.sh` links into place, so it is the same on every machine.
_Avoid_: base config, base install, base ~/.zshrc

**Per-machine file**:
A file outside git that a shared config loads last, holding one machine's own settings.
_Avoid_: local overrides, local config

**Extra**:
A snippet in `<tool>/extras/` that is off by default and that an installer turns on by adding one line to a per-machine file.
_Avoid_: plugin, option, add-on

**Commit hook**:
The check a clone runs before every commit, which can refuse the commit.
_Avoid_: pre-commit hook

**Update reminder**:
The line a new shell shows when a machine hasn't been updated for a while.
_Avoid_: update prompt

**Lockfile**:
A machine's own record of the exact version of each nvim plugin, kept outside the repo.
_Avoid_: lock file
