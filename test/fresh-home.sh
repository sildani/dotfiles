#!/usr/bin/env bash
# Simulates a new machine: copies the repo to ~/src/dotfiles in an empty, seeded
# HOME and runs its install.sh (once with the Oh My Zsh clone failing, then
# twice for real), then doctor.sh and an interactive zsh. Passes when doctor.sh
# --diff shows the seeded files before the install and sums up their backups
# after it (--backups diffs them), the failed run left ~/.zshrc alone, the first
# real run backed up the seeded files, the second changed nothing, doctor exits
# 0 and warns about a stray tmux server only while one runs, zsh starts without
# errors and exports DOTFILES as the repo, tmux loads its config and every extra
# without errors, and every extra turns on from its README line, pasted as is
# (and doctor flags a missing one), and the real repo's working tree is as it
# was. Set KEEP=1 to keep the temp HOME.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="$HOME"
FAKE_HOME="$(mktemp -d)"
LOG="$FAKE_HOME.log"
SHIM_DIR="$FAKE_HOME.bin"
TMUX_SOCKET="fresh-home-$$"
STRAY_SOCKET="fresh-home-stray-$$"

cleanup() {
  tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
  tmux -L "$STRAY_SOCKET" kill-server 2>/dev/null || true
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
  # Again last, so a tail of this script's output shows it.
  echo "FAIL: $1" >&2
  exit 1
}

# Isolation from the real machine:
# - Homebrew's system gitconfig sets the osxkeychain credential helper, which
#   pops a "Keychain Not Found" dialog for a HOME with no keychain.
# - Running inside tmux leaks TMUX_PLUGIN_MANAGER_PATH, which sends TPM's
#   installs to the real ~/.tmux/plugins.
export HOME="$FAKE_HOME" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset TMUX TMUX_PANE TMUX_PLUGIN_MANAGER_PATH XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME DOTFILES

# The real repo's working tree, which a run must leave as it found it: each
# changed or untracked path with its status and content hash, so a rewrite of
# an already-changed file (nvim/lazy-lock.json) shows too.
repo_state() {
  local line path
  git -C "$REAL_REPO_DIR" status --porcelain -z --untracked-files=all |
    while IFS= read -r -d '' line; do
      path="${line:3}"
      [[ "${line:0:1}" == [RC] ]] && IFS= read -r -d '' _  # a rename's old path follows
      printf '%s\t%s\t%s\n' "$path" "${line:0:2}" "$(git -C "$REAL_REPO_DIR" hash-object -- "$path" 2>/dev/null || echo -)"
    done
}

# The working tree (tracked and untracked, not ignored files), copied outside
# ~/code since an installer can clone it anywhere. The install's writes to the
# repo (nvim/lazy-lock.json) land in the copy.
REAL_REPO_DIR="$REPO_DIR"
repo_before="$(repo_state)"
REPO_DIR="$HOME/src/dotfiles"
mkdir -p "$REPO_DIR"
(
  cd "$REAL_REPO_DIR"
  git ls-files -z -co --exclude-standard | while IFS= read -r -d '' f; do
    if [[ -e "$f" ]]; then printf '%s\0' "$f"; fi  # skip deleted, not yet committed
  done | tar --null -T - -cf -
) | tar -xf - -C "$REPO_DIR"
# The copy's, so its REPO_DIR is the copy too. For EXTRAS_ROW_RE.
# shellcheck source=lib/common.sh
source "$REPO_DIR/lib/common.sh"

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

# turn_on_extra <tool>/extras/<name>: appends the README's "Line to add" for
# it to its "Per-machine file", so the test runs what people paste.
turn_on_extra() {
  local row line file
  row="$(grep -F "| \`$1\` " "$REPO_DIR/README.md")" || die "README extras table has no row for $1"
  [[ "$row" =~ $EXTRAS_ROW_RE ]] || die "README row for $1 doesn't end in | \`<line>\` | \`<file>\` |"
  line="${BASH_REMATCH[1]}"
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
# "Only in": the copy leaves out the repo's own (gitignored) local.lua.
grep -qxF "Only in $HOME/.config/nvim/lua: local.lua" <<<"$diff_out" ||  # not a script message: diff's own output
  die "doctor.sh --diff hid the machine's own nvim lua/local.lua"
grep -qF '.config/ghostty/config missing, would be created' <<<"$diff_out" ||
  die "doctor.sh --diff didn't say ~/.config/ghostty/config would be created"
grep -qF 'would also be copied to ~/.zshrc.local' <<<"$diff_out" ||
  die "doctor.sh --diff didn't say ~/.zshrc would be copied to ~/.zshrc.local"
[[ "$(backups)" == 0 && ! -e "$HOME/.zshrc.local" && ! -L "$HOME/.zshrc" ]] || die "doctor.sh --diff changed something"

echo "install.sh with a failing Oh My Zsh clone (should leave ~/.zshrc alone)"
PATH="$SHIM_DIR:$PATH" "$REPO_DIR/install.sh" </dev/null >>"$LOG" 2>&1 &&
  die "install.sh succeeded although the Oh My Zsh clone failed"
[[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" && "$(cat "$HOME/.zshrc")" == "$zshrc_seed" ]] ||
  die "a failed Oh My Zsh clone still replaced ~/.zshrc"
[[ ! -e "$HOME/.zshrc.local" && "$(backups)" == 0 ]] || die "a failed Oh My Zsh clone still moved config"

echo "install.sh, first run (should do what doctor.sh --diff predicted)"
first="$("$REPO_DIR/install.sh" </dev/null 2>&1)" || { echo "$first" >>"$LOG"; die "first install.sh run failed"; }
echo "$first" >>"$LOG"
# expect_predicted <what> <paths install.sh changed> <--diff lines predicting it>:
# a predicting line for each path, and no more lines than paths.
expect_predicted() {
  local path
  while IFS= read -r path; do
    [[ -z "$path" ]] || grep -qF " $path " <<<"$3" ||
      die "install.sh $1 $path, which doctor.sh --diff didn't predict"
  done <<<"$2"
  [[ "$(grep -c . <<<"$3")" == "$(grep -c . <<<"$2")" ]] ||
    die "doctor.sh --diff predicted install.sh $1:"$'\n'"$3"$'\n'"but it $1:"$'\n'"$2"
}
expect_predicted "backed up" "$(sed -nE 's/^  • moved (.*) -> .*/\1/p' <<<"$first")" \
  "$(grep 'would be backed up' <<<"$diff_out")"
expect_predicted "linked" "$(sed -nE 's/^  ✓ (.*) -> .*/\1/p' <<<"$first")" \
  "$(grep -E 'would be (created|backed up and (replaced|linked))' <<<"$diff_out")"
# shellcheck disable=SC2088  # install.sh prints the ~ form
expect_predicted "copied" "$(grep -q '^  • copied ~/.zshrc ' <<<"$first" && echo '~/.zshrc')" \
  "$(grep 'would also be copied to ~/.zshrc.local' <<<"$diff_out")"
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
grep -qF 'Press Space c h in nvim' <<<"$second" || die "install.sh didn't point to NvChad's cheatsheet"
[[ "$(stat -f %i "$HOME/.oh-my-zsh")" == "$omz_inode" ]] || die "second run replaced ~/.oh-my-zsh"
[[ "$(cat "$HOME/.zshrc.local")" == "$zshrc_local" ]] || die "second run changed ~/.zshrc.local"

echo "doctor.sh --diff after install (links match, backups summed up in one line)"
diff_out="$("$REPO_DIR/doctor.sh" --diff 2>&1)" || { echo "$diff_out" >>"$LOG"; die "doctor.sh --diff failed after install"; }
echo "$diff_out" >>"$LOG"
[[ "$(grep -c 'already links to the repo' <<<"$diff_out")" == 4 ]] || die "doctor.sh --diff didn't find all 4 links"
grep -q 'would be' <<<"$diff_out" && die "doctor.sh --diff says install would still change something"
grep -qF "4 backed-up originals differ from the repo (newest: ${backup##*/})" <<<"$diff_out" ||
  die "doctor.sh --diff didn't sum up the 4 backed-up originals"
grep -qE '^(---|\+\+\+|Only in) ' <<<"$diff_out" &&  # not a script message: diff's own output
  die "doctor.sh --diff printed diffs on an installed machine"

echo "doctor.sh --diff --backups (diffs each backed-up original)"
diff_out="$("$REPO_DIR/doctor.sh" --diff --backups 2>&1)" || { echo "$diff_out" >>"$LOG"; die "doctor.sh --diff --backups failed"; }
echo "$diff_out" >>"$LOG"
for f in .tmux.conf .zshrc .config/nvim "Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
  grep -qF "${backup/#$HOME/~}/$f:" <<<"$diff_out" || die "doctor.sh --diff --backups didn't show backed-up $f"
done
grep -qxF -- '-# old tmux config' <<<"$diff_out" ||  # not a script message: a seeded line
  die "doctor.sh --diff --backups didn't diff the backed-up ~/.tmux.conf"

echo "doctor.sh"
doctor_out="$("$REPO_DIR/doctor.sh" 2>&1)" || { echo "$doctor_out" >>"$LOG"; die "doctor.sh reported problems"; }
echo "$doctor_out" >>"$LOG"
grep -qF 'tmux servers besides the default one are running' <<<"$doctor_out" &&
  die "doctor.sh warned about stray tmux servers with none running (stop any left over and rerun)"

echo "doctor.sh with a stray tmux server (should warn, naming it, and still pass)"
tmux -L "$STRAY_SOCKET" -f /dev/null new-session -d >>"$LOG" 2>&1 || die "tmux didn't start"
doctor_out="$("$REPO_DIR/doctor.sh" 2>&1)" || { echo "$doctor_out" >>"$LOG"; die "doctor.sh failed with a stray tmux server"; }
tmux -L "$STRAY_SOCKET" kill-server
echo "$doctor_out" >>"$LOG"
grep 'tmux servers besides the default one are running' <<<"$doctor_out" | grep -qF "$STRAY_SOCKET" ||
  die "doctor.sh didn't warn about the stray tmux server $STRAY_SOCKET"

# A clean environment, so the real shell's ZDOTDIR or ZSH can't leak in.
echo "interactive zsh"
zsh_out="$(env -i HOME="$HOME" PATH="$PATH" TERM=xterm-256color zsh -i -c exit 2>&1)"
[[ -z "$zsh_out" ]] || die "an interactive zsh printed: $zsh_out"
zsh_dotfiles="$(env -i HOME="$HOME" PATH="$PATH" TERM=xterm-256color zsh -i -c 'printenv DOTFILES' 2>&1)" || true
[[ "$zsh_dotfiles" == "$(cd "$REPO_DIR" && pwd -P)" ]] || die "zsh exported DOTFILES='$zsh_dotfiles', not the repo at $REPO_DIR"

# Commands, not -f: a server started with -f exits 0 even when the file has
# errors, while source-file as a command exits non-zero on any.
echo "tmux config and every tmux extra load without errors"
tmux -L "$TMUX_SOCKET" -f /dev/null new-session -d >>"$LOG" 2>&1 || die "tmux didn't start"
for f in "$HOME/.tmux.conf" "$REPO_DIR"/tmux/extras/*; do
  tmux -L "$TMUX_SOCKET" source-file "$f" >>"$LOG" 2>&1 || die "tmux reports errors in ${f/#$HOME/~}"
done
for opt in set-clipboard allow-passthrough; do
  [[ "$(tmux -L "$TMUX_SOCKET" show -gv "$opt" 2>>"$LOG")" == on ]] || die "tmux config or an extra left $opt off"
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
# Started from zsh, as people do, so the server has DOTFILES for the extras lines.
# shellcheck disable=SC2016  # $TMUX_SOCKET is for the inner zsh
env -i HOME="$HOME" PATH="$PATH" TERM=xterm-256color TMUX_SOCKET="$TMUX_SOCKET" \
  zsh -i -c 'tmux -L "$TMUX_SOCKET" -f /dev/null new-session -d \; source-file ~/.tmux.conf' >>"$LOG" 2>&1 ||
  die "tmux started from zsh reports errors with the extras on"
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
# shellcheck disable=SC2016  # a literal tmux line
echo 'source-file "$DOTFILES/tmux/extras/no-such-extra.conf"' >"$HOME/.tmux.local.conf"
"$REPO_DIR/doctor.sh" >>"$LOG" 2>&1 && die "doctor.sh passed with a missing tmux extra"
rm "$HOME/.tmux.local.conf"

echo "real repo's working tree unchanged"
repo_after="$(repo_state)"
changed="$(comm -3 <(sort <<<"$repo_before") <(sort <<<"$repo_after") | sed -e '/^$/d' -e $'s/^\t//' | cut -f1 | sort -u)"
[[ -z "$changed" ]] || die "the run changed the real repo at $REAL_REPO_DIR:"$'\n'"$changed"

echo "PASS"
