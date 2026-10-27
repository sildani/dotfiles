# dotfiles

Shared terminal setup (zsh, tmux, nvim, Ghostty) for several macOS machines, one personal and the rest pull-only.

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
