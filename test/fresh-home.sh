#!/usr/bin/env bash
# Simulates a new machine: runs install.sh twice against an empty, seeded HOME,
# then doctor.sh. Passes when doctor exits 0, the first run backed up the seeded
# files, and the second run changed nothing. Set KEEP=1 to keep the temp HOME.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="$HOME"
FAKE_HOME="$(mktemp -d)"
LOG="$FAKE_HOME.log"

cleanup() {
  if [[ "${KEEP:-}" == 1 ]]; then
    echo "kept: $FAKE_HOME (log: $LOG)"
  else
    rm -rf "$FAKE_HOME" "$LOG"
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
echo '# old zsh config' >"$HOME/.zshrc"

backups() { find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '; }

echo "fresh HOME: $HOME"
echo "install.sh, first run"
"$REPO_DIR/install.sh" </dev/null >>"$LOG" 2>&1 || die "first install.sh run failed"
[[ "$(backups)" == 1 ]] || die "expected 1 backup folder after the first run, found $(backups)"
backup="$(find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1)"
for f in .tmux.conf .zshrc .config/nvim/init.lua "Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
  [[ -e "$backup/$f" ]] || die "seeded file was not backed up: $f"
done
[[ ! -e "$ghostty_lib/config.ghostty" ]] || die "Ghostty Library config still in place"

echo "install.sh, second run (should change nothing)"
"$REPO_DIR/install.sh" </dev/null >>"$LOG" 2>&1 || die "second install.sh run failed"
[[ "$(backups)" == 1 ]] || die "second run created a new backup folder"

echo "doctor.sh"
"$REPO_DIR/doctor.sh" >>"$LOG" 2>&1 || die "doctor.sh reported problems"

echo "PASS"
