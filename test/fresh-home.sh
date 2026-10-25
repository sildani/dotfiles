#!/usr/bin/env bash
# Simulates a new machine: runs install.sh against an empty, seeded HOME (once
# with the Oh My Zsh clone failing, then twice for real), then doctor.sh and an
# interactive zsh. Passes when the failed run left ~/.zshrc alone, the first
# real run backed up the seeded files, the second changed nothing, doctor exits
# 0, and zsh starts without errors. Set KEEP=1 to keep the temp HOME.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="$HOME"
FAKE_HOME="$(mktemp -d)"
LOG="$FAKE_HOME.log"
SHIM_DIR="$FAKE_HOME.bin"

cleanup() {
  if [[ "${KEEP:-}" == 1 ]]; then
    echo "kept: $FAKE_HOME (log: $LOG)"
  else
    rm -rf "$FAKE_HOME" "$LOG" "$SHIM_DIR"
  fi
}
trap cleanup EXIT

die() {
  echo "FAIL: $1" >&2
  echo "--- last lines of $LOG" >&2
  tail -30 "$LOG" >&2
  exit 1
}

# Isolation from the real machine:
# - Homebrew's system gitconfig sets the osxkeychain credential helper, which
#   pops a "Keychain Not Found" dialog for a HOME with no keychain.
# - Running inside tmux leaks TMUX_PLUGIN_MANAGER_PATH, which sends TPM's
#   installs to the real ~/.tmux/plugins.
export HOME="$FAKE_HOME" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset TMUX TMUX_PANE TMUX_PLUGIN_MANAGER_PATH XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME

# Reuse the real font when present so brew isn't needed for it locally.
mkdir -p "$HOME/Library/Fonts"
for f in "$REAL_HOME"/Library/Fonts/HurmitNerdFont*; do
  [[ -e "$f" ]] && ln -s "$f" "$HOME/Library/Fonts/"
done

# Pre-existing config the install must back up.
ghostty_lib="$HOME/Library/Application Support/com.mitchellh.ghostty"
mkdir -p "$ghostty_lib" "$HOME/.config/nvim"
echo 'font-size = 20' >"$ghostty_lib/config.ghostty"
echo '-- old config' >"$HOME/.config/nvim/init.lua"
echo '# old tmux config' >"$HOME/.tmux.conf"
# shellcheck disable=SC2016  # a literal zshrc line, not expanded here
printf '%s\n' '# old zsh config' 'source $ZSH/oh-my-zsh.sh' >"$HOME/.zshrc"

backups() { find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '; }

echo "fresh HOME: $HOME"

# A git that fails only the Oh My Zsh clone, as with no network.
mkdir -p "$SHIM_DIR"
printf '#!/bin/sh\ncase "$*" in *ohmyzsh*) echo "simulated clone failure" >&2; exit 128 ;; esac\nexec %s "$@"\n' \
  "$(command -v git)" >"$SHIM_DIR/git"
chmod +x "$SHIM_DIR/git"
zshrc_seed="$(cat "$HOME/.zshrc")"

echo "install.sh with a failing Oh My Zsh clone (should leave ~/.zshrc alone)"
PATH="$SHIM_DIR:$PATH" "$REPO_DIR/install.sh" </dev/null >>"$LOG" 2>&1 &&
  die "install.sh succeeded although the Oh My Zsh clone failed"
[[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" && "$(cat "$HOME/.zshrc")" == "$zshrc_seed" ]] ||
  die "a failed Oh My Zsh clone still replaced ~/.zshrc"
[[ ! -e "$HOME/.zshrc.local" && "$(backups)" == 0 ]] || die "a failed Oh My Zsh clone still moved config"

echo "install.sh, first run"
"$REPO_DIR/install.sh" </dev/null >>"$LOG" 2>&1 || die "first install.sh run failed"
[[ "$(backups)" == 1 ]] || die "expected 1 backup folder after the first run, found $(backups)"
backup="$(find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1)"
for f in .tmux.conf .zshrc .config/nvim/init.lua "Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
  [[ -e "$backup/$f" ]] || die "seeded file was not backed up: $f"
done
[[ ! -e "$ghostty_lib/config.ghostty" ]] || die "Ghostty Library config still in place"
grep -qx '# old zsh config' "$HOME/.zshrc.local" || die "old ~/.zshrc was not copied to ~/.zshrc.local"
grep -q '^source' "$HOME/.zshrc.local" && die ".zshrc.local still loads Oh My Zsh itself"
zsh -n "$HOME/.zshrc.local" || die ".zshrc.local is not valid zsh"
zshrc_local="$(cat "$HOME/.zshrc.local")"
omz_inode="$(stat -f %i "$HOME/.oh-my-zsh")"

echo "install.sh, second run (should change nothing)"
second="$("$REPO_DIR/install.sh" </dev/null 2>&1)" || { echo "$second" >>"$LOG"; die "second install.sh run failed"; }
echo "$second" >>"$LOG"
[[ "$(backups)" == 1 ]] || die "second run created a new backup folder"
# These are install.sh's messages for each change it makes; keep them in sync.
changes="$(grep -E 'moved |cloned |copied |✓ [^ ]+ -> ' <<<"$second" || true)"
[[ -z "$changes" ]] || die "second run changed something: $changes"
[[ "$(stat -f %i "$HOME/.oh-my-zsh")" == "$omz_inode" ]] || die "second run replaced ~/.oh-my-zsh"
[[ "$(cat "$HOME/.zshrc.local")" == "$zshrc_local" ]] || die "second run changed ~/.zshrc.local"

echo "doctor.sh"
"$REPO_DIR/doctor.sh" >>"$LOG" 2>&1 || die "doctor.sh reported problems"

# A clean environment, so the real shell's ZDOTDIR or ZSH can't leak in.
echo "interactive zsh"
zsh_out="$(env -i HOME="$HOME" PATH="$PATH" TERM=xterm-256color zsh -i -c exit 2>&1)"
[[ -z "$zsh_out" ]] || die "an interactive zsh printed: $zsh_out"

echo "PASS"
