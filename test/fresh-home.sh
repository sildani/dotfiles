#!/usr/bin/env bash
# Simulates a new machine: runs install.sh against an empty, seeded HOME (once
# with the Oh My Zsh clone failing, then twice for real), then doctor.sh and an
# interactive zsh. Passes when doctor.sh --diff shows the seeded files before
# the install and their backups after it, the failed run left ~/.zshrc alone,
# the first real run backed up the seeded files, the second changed nothing, doctor exits
# 0, zsh starts without errors, tmux loads its config and every extra without
# errors, and every extra turns on from its README line (and doctor flags a
# missing one). Set KEEP=1 to keep the temp HOME.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="$HOME"
FAKE_HOME="$(mktemp -d)"
LOG="$FAKE_HOME.log"
SHIM_DIR="$FAKE_HOME.bin"
TMUX_SOCKET="fresh-home-$$"

cleanup() {
  tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
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
mkdir -p "$HOME/.config/nvim/lua"
echo '-- old per-machine config' >"$HOME/.config/nvim/lua/local.lua"
echo '# old tmux config' >"$HOME/.tmux.conf"
# shellcheck disable=SC2016  # a literal zshrc line, not expanded here
printf '%s\n' '# old zsh config' 'source $ZSH/oh-my-zsh.sh' >"$HOME/.zshrc"

# turn_on_extra <tool>/extras/<name>: appends the README's "Add this line" for
# it to the file the row names, so the test runs what people paste.
turn_on_extra() {
  # shellcheck disable=SC2016  # literal backticks in a regex
  local re='`([^`]+)` to `([^`]+)` *\|[[:space:]]*$' row line file
  row="$(grep -F "| \`$1\` " "$REPO_DIR/README.md")" || die "README extras table has no row for $1"
  [[ "$row" =~ $re ]] || die "README row for $1 doesn't end in \`<line>\` to \`<file>\`"
  line="${BASH_REMATCH[1]//\~\/code\/dotfiles/$REPO_DIR}"
  file="${BASH_REMATCH[2]/#\~/$HOME}"
  echo "$line" >>"$file"
}

backups() { find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' '; }

echo "fresh HOME: $HOME"

# A git that fails only the Oh My Zsh clone, as with no network.
mkdir -p "$SHIM_DIR"
printf '#!/bin/sh\ncase "$*" in *ohmyzsh*) echo "simulated clone failure" >&2; exit 128 ;; esac\nexec %s "$@"\n' \
  "$(command -v git)" >"$SHIM_DIR/git"
chmod +x "$SHIM_DIR/git"
zshrc_seed="$(cat "$HOME/.zshrc")"

echo "doctor.sh --diff before install (should show the seeded files and change nothing)"
diff_out="$("$REPO_DIR/doctor.sh" --diff 2>&1)" || { echo "$diff_out" >>"$LOG"; die "doctor.sh --diff failed"; }
echo "$diff_out" >>"$LOG"
for line in '-# old tmux config' '-# old zsh config' '--- old config' '-font-size = 20'; do
  grep -qxF -- "$line" <<<"$diff_out" || die "doctor.sh --diff didn't show seeded line: $line"
done
# "Only in" here; a content diff where the repo has its own (gitignored) local.lua.
grep -qxE "Only in $HOME/.config/nvim/lua: local.lua|--- old per-machine config" <<<"$diff_out" ||
  die "doctor.sh --diff hid the machine's own nvim lua/local.lua"
grep -qF '.config/ghostty/config missing, would be created' <<<"$diff_out" ||
  die "doctor.sh --diff didn't say ~/.config/ghostty/config would be created"
grep -qF 'would be copied to ~/.zshrc.local' <<<"$diff_out" ||
  die "doctor.sh --diff didn't say ~/.zshrc would be copied to ~/.zshrc.local"
[[ "$(backups)" == 0 && ! -e "$HOME/.zshrc.local" && ! -L "$HOME/.zshrc" ]] || die "doctor.sh --diff changed something"

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
grep -q 'optional extras' <<<"$second" || die "install.sh didn't point to the optional extras"
[[ "$(stat -f %i "$HOME/.oh-my-zsh")" == "$omz_inode" ]] || die "second run replaced ~/.oh-my-zsh"
[[ "$(cat "$HOME/.zshrc.local")" == "$zshrc_local" ]] || die "second run changed ~/.zshrc.local"

echo "doctor.sh --diff after install (links match, backed-up originals differ)"
diff_out="$("$REPO_DIR/doctor.sh" --diff 2>&1)" || { echo "$diff_out" >>"$LOG"; die "doctor.sh --diff failed after install"; }
echo "$diff_out" >>"$LOG"
[[ "$(grep -c 'already links to the repo' <<<"$diff_out")" == 4 ]] || die "doctor.sh --diff didn't find all 4 links"
grep -q 'would be' <<<"$diff_out" && die "doctor.sh --diff says install would still change something"
for f in .tmux.conf .zshrc .config/nvim "Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
  grep -qF "${backup/#$HOME/~}/$f:" <<<"$diff_out" || die "doctor.sh --diff didn't show backed-up $f"
done
grep -qxF -- '-# old tmux config' <<<"$diff_out" || die "doctor.sh --diff didn't diff the backed-up ~/.tmux.conf"

echo "doctor.sh"
"$REPO_DIR/doctor.sh" >>"$LOG" 2>&1 || die "doctor.sh reported problems"

# A clean environment, so the real shell's ZDOTDIR or ZSH can't leak in.
echo "interactive zsh"
zsh_out="$(env -i HOME="$HOME" PATH="$PATH" TERM=xterm-256color zsh -i -c exit 2>&1)"
[[ -z "$zsh_out" ]] || die "an interactive zsh printed: $zsh_out"

# Commands, not -f: a server started with -f exits 0 even when the file has
# errors, while source-file as a command exits non-zero on any.
echo "tmux config and every tmux extra load without errors"
tmux -L "$TMUX_SOCKET" -f /dev/null new-session -d >>"$LOG" 2>&1 || die "tmux didn't start"
for f in "$HOME/.tmux.conf" "$REPO_DIR"/tmux/extras/*; do
  tmux -L "$TMUX_SOCKET" source-file "$f" >>"$LOG" 2>&1 || die "tmux reports errors in ${f/#$HOME/~}"
done
tmux -L "$TMUX_SOCKET" kill-server

echo "every extra turned on with its README line"
for f in "$REPO_DIR"/*/extras/*; do turn_on_extra "${f#"$REPO_DIR"/}"; done
doctor_out="$("$REPO_DIR/doctor.sh" 2>&1)" || { echo "$doctor_out" >>"$LOG"; die "doctor.sh failed with every extra on"; }
echo "$doctor_out" >>"$LOG"
grep -q 'optional extras' <<<"$doctor_out" || die "doctor.sh didn't point to the optional extras"
for f in "$REPO_DIR"/*/extras/*; do
  tool="${f#"$REPO_DIR"/}" tool="${tool%%/*}"
  grep -qF "$tool extra on: ${f##*/}" <<<"$doctor_out" ||
    die "doctor.sh didn't list ${f##*/}; does its README line point at it?"
done
tmux -L "$TMUX_SOCKET" -f /dev/null new-session -d \; source-file "$HOME/.tmux.conf" >>"$LOG" 2>&1 ||
  die "tmux reports errors with the extras on"
tmux -L "$TMUX_SOCKET" list-keys -T prefix C-k 2>>"$LOG" | grep -q 'send-keys C-k' ||
  die "agy-ctrl-k.conf didn't bind prefix C-k"
tmux -L "$TMUX_SOCKET" kill-server
# shellcheck disable=SC2016  # $PROMPT is for the inner zsh
prompt="$(env -i HOME="$HOME" PATH="$PATH" TERM=xterm-256color zsh -i -c 'print -P "$PROMPT"' 2>&1)"
echo "prompt: $prompt" >>"$LOG"
grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' <<<"$prompt" || die "utc-prompt.zsh's prompt has no timestamp: $prompt"
rm "$HOME/.tmux.local.conf"
printf '%s\n' "$zshrc_local" >"$HOME/.zshrc.local"

echo "tmux extra missing from the repo"
echo "source-file $REPO_DIR/tmux/extras/no-such-extra.conf" >"$HOME/.tmux.local.conf"
"$REPO_DIR/doctor.sh" >>"$LOG" 2>&1 && die "doctor.sh passed with a missing tmux extra"
rm "$HOME/.tmux.local.conf"

echo "PASS"
