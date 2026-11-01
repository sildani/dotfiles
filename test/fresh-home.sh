#!/usr/bin/env bash
# Simulates a new machine: copies the repo to ~/src/dotfiles in an empty, seeded
# HOME and runs its install.sh (once with the Oh My Zsh clone failing, then
# twice for real), then doctor.sh and an interactive zsh. Passes when a throwaway
# clone gets the commit hook, which refuses a commit when a fast test fails, and
# keeps a core.hooksPath of its own with a warning, Rectangle is installed only if missing and a failed cask only warns,
# the install sets the hook in the copy, which then refuses a commit on
# main, without writing ~/.gitconfig, doctor.sh lists every tool, doctor.sh
# --diff shows the seeded files before the install and sums up their backups
# after it (--backups diffs them), the failed run left ~/.zshrc alone, the first
# real run backed up the seeded files, copied only the old ~/.zshrc's own lines
# to ~/.zshrc.local (warning about its plugins the shared zshrc lacks), linked
# ~/.zshrc.example to Oh My Zsh's template and ~/.tmux/resurrect to resurrect's
# saves, wrote this machine's nvim lockfile outside the repo and started the
# update reminder's clock, the second changed nothing (not even a real
# ~/.tmux/resurrect or that clock), doctor exits 0, fails naming a missing nvim
# plugin and warns about a stray tmux server only while one runs and about
# ssh-agent in ~/.zprofile only while a line there starts one, update.sh runs
# for real, apart from brew upgrades, and leaves doctor healthy, zsh starts without errors and exports DOTFILES as
# the repo and EDITOR and VISUAL as nvim (which ~/.zshrc.local overrides), keeps
# PATH free of duplicates and in order, nested too, and stays on the emacs
# keymap, tmux loads its config and every extra without errors, and every
# extra turns on from its README line, pasted as is
# (and doctor flags a missing one), Ghostty accepts its config and every extra,
# reads the shared config's window settings and ghostty/extras/window-frame.conf
# undoes them, and the real repo's working tree is as it was. Set KEEP=1 to keep
# the temp HOME.
set -euo pipefail
# shellcheck source=lib/test-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-guard.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOME="$HOME"
FAKE_HOME="$(mktemp -d)"
LOG="$FAKE_HOME.log"
SHIM_DIR="$FAKE_HOME.bin"
HOOK_CLONE="$FAKE_HOME.clone"
BREW_SHIM_DIR="$FAKE_HOME.brew"
TMUX_SOCKET="fresh-home-$$"
STRAY_SOCKET="fresh-home-stray-$$"

cleanup() {
  tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
  tmux -L "$STRAY_SOCKET" kill-server 2>/dev/null || true
  if [[ "${KEEP:-}" == 1 ]]; then
    echo "kept: $FAKE_HOME (log: $LOG)"
  else
    rm -rf "$FAKE_HOME" "$LOG" "$SHIM_DIR" "$HOOK_CLONE" "$BREW_SHIM_DIR"
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
# - An inherited SSH_AGENT_PID or SSH_AUTH_SOCK reaches the real agent, and
#   ssh-agent -k would stop it.
export HOME="$FAKE_HOME" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset TMUX TMUX_PANE TMUX_PLUGIN_MANAGER_PATH XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME DOTFILES SSH_AGENT_PID SSH_AUTH_SOCK

# The real repo's working tree, which a run must leave as it found it: each
# changed or untracked path with its status and content hash, so a rewrite of
# an already-changed file shows too.
repo_state() {
  local line path
  git -C "$REAL_REPO_DIR" status --porcelain -z --untracked-files=all |
    while IFS= read -r -d '' line; do
      path="${line:3}"
      [[ "${line:0:1}" == [RC] ]] && IFS= read -r -d '' _  # a rename's old path follows
      printf '%s\t%s\t%s\n' "$path" "${line:0:2}" "$(git -C "$REAL_REPO_DIR" hash-object -- "$path" 2>/dev/null || echo -)"
    done
}

# The working tree, copied outside ~/code since an installer can clone it
# anywhere. Anything the install writes to the repo lands in the copy.
REAL_REPO_DIR="$REPO_DIR"
repo_before="$(repo_state)"
head_before="$(git -C "$REAL_REPO_DIR" rev-parse HEAD)"
# The real repo's, for copy_worktree. The copy's replaces it below.
# shellcheck source=lib/common.sh
source "$REAL_REPO_DIR/lib/common.sh"
REPO_DIR="$HOME/src/dotfiles"
copy_worktree "$REAL_REPO_DIR" "$REPO_DIR"
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
# In the shapes of Oh My Zsh's template, plus the machine's own lines, among
# them a setting Oh My Zsh reads at runtime, which works in ~/.zshrc.local.
# shellcheck disable=SC2016  # literal zshrc lines, not expanded here
zshrc_own=('export PATH="$HOME/bin:$PATH"' "alias ll='ls -la'" 'DISABLE_AUTO_TITLE="true"')
# shellcheck disable=SC2016
printf '%s\n' '# old zsh config' '# If you come from bash you might have to change your $PATH.' '' '' \
  'export ZSH="$HOME/.oh-my-zsh"' 'export ZSH_THEME="robbyrussell"' 'HIST_STAMPS="mm/dd/yyyy"' \
  'export ZSH_CUSTOM="$HOME/omz-custom"' "zstyle ':omz:update' mode disabled" "zstyle ':omz:update' frequency 7" 'plugins=(' '  git' '  docker' ')' \
  'source $ZSH/oh-my-zsh.sh' 'eval "$(/opt/homebrew/bin/brew shellenv)"' "${zshrc_own[@]}" >"$HOME/.zshrc"

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

# ghostty_expect <context> <setting> <value>: the value Ghostty ends up with
# once it has loaded ~/.config/ghostty/config and everything that pulls in.
ghostty_expect() {
  local got
  got="$("$(ghostty_app)/Contents/MacOS/ghostty" +show-config --changes-only=false 2>>"$LOG" | sed -n "s/^$2 = //p")" ||
    die "$1: ghostty +show-config failed"
  [[ "$got" == "$3" ]] || die "$1: Ghostty has $2 = '$got', not '$3'"
}

echo "fresh HOME: $HOME"

# hook_commit: an empty commit in the throwaway clone, through its hook.
hook_commit() { git -C "$HOOK_CLONE" -c user.name=t -c user.email=t@localhost commit -q --allow-empty -m check; }

echo "a clone gets the commit hook, and keeps a core.hooksPath of its own"
git clone -q "$REPO_DIR" "$HOOK_CLONE"
enable_commit_hook "$HOOK_CLONE" >>"$LOG"
[[ "$(git -C "$HOOK_CLONE" config --local core.hooksPath)" == hooks ]] || die "enable_commit_hook didn't set core.hooksPath to hooks"
git -C "$HOOK_CLONE" config --local core.hooksPath other-hooks
hook_out="$(enable_commit_hook "$HOOK_CLONE")"
[[ "$(git -C "$HOOK_CLONE" config --local core.hooksPath)" == other-hooks ]] || die "enable_commit_hook replaced a core.hooksPath of the clone's own"
[[ "$hook_out" == *"other-hooks"* ]] || die "enable_commit_hook didn't warn about core.hooksPath other-hooks: $hook_out"

echo "the commit hook refuses a commit when a fast test fails"
git -C "$HOOK_CLONE" config --local core.hooksPath hooks
git -C "$HOOK_CLONE" switch -q -c hook-check
hook_tests=(lint doctor-warnings updates)
# Stand-ins that also fail if git's variables reach the tests' temp repos.
for name in "${hook_tests[@]}"; do
  # shellcheck disable=SC2016  # for the stand-in to expand
  printf '#!/bin/sh\n[ -z "$GIT_INDEX_FILE$GIT_DIR" ]\n' >"$HOOK_CLONE/test/$name.sh"
done
hook_commit 2>>"$LOG" || die "the commit hook refused a commit with every test passing"
for name in "${hook_tests[@]}"; do
  cp "$HOOK_CLONE/test/$name.sh" "$HOOK_CLONE/test/$name.sh.keep"
  printf '#!/bin/sh\nexit 1\n' >"$HOOK_CLONE/test/$name.sh"
  hook_commit 2>>"$LOG" && die "the commit hook let a commit through with test/$name.sh failing"
  mv "$HOOK_CLONE/test/$name.sh.keep" "$HOOK_CLONE/test/$name.sh"
done

# A git that fails only the Oh My Zsh clone, as with no network.
mkdir -p "$SHIM_DIR"
printf '#!/bin/sh\ncase "$*" in *ohmyzsh*) echo "simulated clone failure" >&2; exit 128 ;; esac\nexec %s "$@"\n' \
  "$(command -v git)" >"$SHIM_DIR/git"
chmod +x "$SHIM_DIR/git"
zshrc_seed="$(cat "$HOME/.zshrc")"

echo "Rectangle installs only if missing, and a failed cask only warns"
mkdir -p "$BREW_SHIM_DIR" "$HOME/Applications"
printf '#!/bin/sh\necho "$*" >>"%s/calls"\nexit 1\n' "$BREW_SHIM_DIR" >"$BREW_SHIM_DIR/brew"
chmod +x "$BREW_SHIM_DIR/brew"
# Run in a subshell: this changes PATH and APP_DIRS.
rectangle_with_fake_brew() { PATH="$BREW_SHIM_DIR:$PATH" APP_DIRS=("$HOME/Applications"); install_rectangle 2>&1; }
rectangle_out="$(rectangle_with_fake_brew)" ||
  die "a failed Rectangle cask stopped the install"
[[ "$(cat "$BREW_SHIM_DIR/calls")" == 'install --cask rectangle' ]] || die "install_rectangle ran brew as: $(cat "$BREW_SHIM_DIR/calls")"
[[ "$rectangle_out" == *"couldn't install Rectangle"* ]] || die "a failed Rectangle cask didn't warn: $rectangle_out"
mkdir "$HOME/Applications/Rectangle.app"
rm "$BREW_SHIM_DIR/calls"
rectangle_out="$(rectangle_with_fake_brew)"
[[ ! -e "$BREW_SHIM_DIR/calls" ]] || die "install_rectangle ran brew with Rectangle.app present: $rectangle_out"
rm -rf "$HOME/Applications/Rectangle.app"

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
[[ "$(git -C "$REPO_DIR" config --local core.hooksPath)" == hooks ]] || die "install.sh didn't set core.hooksPath in the clone"
[[ ! -e "$HOME/.gitconfig" ]] || die "install.sh wrote ~/.gitconfig"
git -C "$REPO_DIR" switch -q -C main
refused="$(git -C "$REPO_DIR" -c user.name=t -c user.email=t@localhost commit --allow-empty -m refused 2>&1)" &&
  die "a commit on main in the installed clone wasn't refused"
[[ "$refused" == *"refusing to commit on main"* ]] || die "the commit failed, but not through the hook: $refused"
backup="$(find "$HOME/.dotfiles-backup" -mindepth 1 -maxdepth 1)"
for f in .tmux.conf .zshrc .config/nvim/init.lua "Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
  [[ -e "$backup/$f" ]] || die "seeded file was not backed up: $f"
done
[[ ! -e "$ghostty_lib/config.ghostty" ]] || die "Ghostty Library config still in place"
[[ "$(grep -v '^#' "$HOME/.zshrc.local")" == "$(printf '%s\n' "${zshrc_own[@]}")" ]] ||
  die "the copied ~/.zshrc.local isn't the header plus the old ~/.zshrc's own lines:"$'\n'"$(cat "$HOME/.zshrc.local")"
{ grep -qF "${backup/#$HOME/~}/.zshrc" "$HOME/.zshrc.local" && grep -qF 'is at ~/.zshrc.example' "$HOME/.zshrc.local"; } ||
  die "the copied ~/.zshrc.local's header doesn't point to the backup and ~/.zshrc.example"
grep -q '^source' "$HOME/.zshrc.local" && die ".zshrc.local still loads Oh My Zsh itself"
[[ "$(readlink "$HOME/.zshrc.example")" == "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" ]] ||
  die "first run didn't link ~/.zshrc.example to Oh My Zsh's template"
omz_lacks="$(grep 'Oh My Zsh settings the shared zshrc lacks' <<<"$first")" ||
  die "install.sh didn't warn about the old ~/.zshrc's plugins the shared zshrc lacks"
[[ " $omz_lacks " == *" docker "* && " $omz_lacks " != *" git "* ]] ||
  die "install.sh should name plugin docker, and not git: $omz_lacks"
[[ "$omz_lacks" == *'HIST_STAMPS="mm/dd/yyyy"'* && "$omz_lacks" == *"zstyle ':omz:update' frequency 7"* ]] ||
  die "install.sh should name HIST_STAMPS and zstyle ':omz:update', which load too late in ~/.zshrc.local: $omz_lacks"
[[ "$omz_lacks" != *"mode disabled"* ]] ||
  die "install.sh shouldn't name zstyle ':omz:update' mode disabled, which the shared zshrc sets: $omz_lacks"
[[ "$omz_lacks" == *'export ZSH_CUSTOM='* && "$omz_lacks" != *ZSH_THEME* ]] ||
  die "install.sh should name export ZSH_CUSTOM, and not export ZSH_THEME, which matches the shared zshrc: $omz_lacks"
zsh -n "$HOME/.zshrc.local" || die ".zshrc.local is not valid zsh"
nvim_lock="$HOME/.local/state/nvim/lazy-lock.json"
[[ -s "$nvim_lock" ]] || die "first run didn't write this machine's nvim lockfile at $nvim_lock"
[[ ! -e "$REPO_DIR/nvim/lazy-lock.json" ]] || die "first run wrote a lockfile into the repo"
# Written in full: lazy.nvim itself, and a plugin NvChad's spec imports.
for name in lazy.nvim NvChad base46; do
  grep -q "^  \"$name\": " "$nvim_lock" || die "the nvim lockfile has no $name"
done
[[ -f "$HOME/.local/state/dotfiles/last-update" ]] || die "first run didn't start the update reminder's clock"
touch -t 202001010000 "$HOME/.local/state/dotfiles/last-update"
resurrect_saves="$HOME/.local/share/tmux/resurrect"
[[ -L "$HOME/.tmux/resurrect" && "$(readlink "$HOME/.tmux/resurrect")" == "$resurrect_saves" && -d "$resurrect_saves" ]] ||
  die "first run didn't link ~/.tmux/resurrect to the folder $resurrect_saves"
grep -qF '• linked ~/.tmux/resurrect -> ' <<<"$first" || die "install.sh didn't say it linked ~/.tmux/resurrect"
zshrc_local="$(cat "$HOME/.zshrc.local")"
omz_inode="$(stat -f %i "$HOME/.oh-my-zsh")"
# A real ~/.tmux/resurrect folder, as on a machine that saved there before the
# link, which the second run should leave alone.
rm "$HOME/.tmux/resurrect"
mkdir "$HOME/.tmux/resurrect"
echo 'old save' >"$HOME/.tmux/resurrect/tmux_resurrect_old.txt"

echo "install.sh, second run (should change nothing)"
second="$("$REPO_DIR/install.sh" </dev/null 2>&1)" || { echo "$second" >>"$LOG"; die "second install.sh run failed"; }
echo "$second" >>"$LOG"
[[ "$(backups)" == 1 ]] || die "second run created a new backup folder"
# These are install.sh's messages for each change it makes; keep them in sync.
changes="$(grep -E 'moved |cloned |copied |linked |✓ [^ ]+ -> ' <<<"$second" || true)"
[[ -z "$changes" ]] || die "second run changed something: $changes"
grep -q 'optional extras' <<<"$second" || die "install.sh didn't point to the optional extras"
grep -qF 'Press Space c h in nvim' <<<"$second" || die "install.sh didn't point to NvChad's cheatsheet"
[[ "$(stat -f %i "$HOME/.oh-my-zsh")" == "$omz_inode" ]] || die "second run replaced ~/.oh-my-zsh"
[[ "$(cat "$HOME/.zshrc.local")" == "$zshrc_local" ]] || die "second run changed ~/.zshrc.local"
[[ ! -L "$HOME/.tmux/resurrect" && "$(cat "$HOME/.tmux/resurrect/tmux_resurrect_old.txt")" == 'old save' ]] ||
  die "second run changed the real ~/.tmux/resurrect folder"
[[ -n "$(find "$HOME/.local/state/dotfiles/last-update" -mtime +1)" ]] || die "second run restarted the update reminder's clock"

echo "doctor.sh --diff after install (links match, backups summed up in one line)"
diff_out="$("$REPO_DIR/doctor.sh" --diff 2>&1)" || { echo "$diff_out" >>"$LOG"; die "doctor.sh --diff failed after install"; }
echo "$diff_out" >>"$LOG"
[[ "$(grep -c 'already links to the repo' <<<"$diff_out")" == "${#LINKS[@]}" ]] || die "doctor.sh --diff didn't find all ${#LINKS[@]} links"
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
for entry in "${FORMULAE[@]}"; do
  IFS=: read -r _ cmd _ <<<"$entry"
  [[ "$doctor_out" =~ ✓\ $cmd\ [0-9] ]] || die "doctor.sh doesn't list $cmd with its version"
done
grep -qF 'tmux servers besides the default one are running' <<<"$doctor_out" &&
  die "doctor.sh warned about stray tmux servers with none running (stop any left over and rerun)"
grep -qF 'ssh-agent in ~/.zprofile' <<<"$doctor_out" &&
  die "doctor.sh warned about ssh-agent in ~/.zprofile with no ~/.zprofile"

echo "doctor.sh with ssh-agent in ~/.zprofile (should warn, counting agents, with the fix, and still pass; a comment or a socket path shouldn't)"
# shellcheck disable=SC2016  # literal lines for ~/.zprofile
printf '%s\n' '# eval "$(ssh-agent -s)"' 'export SSH_AUTH_SOCK=~/.ssh/ssh-agent.sock' >"$HOME/.zprofile"
doctor_out="$("$REPO_DIR/doctor.sh" 2>&1)" || { echo "$doctor_out" >>"$LOG"; die "doctor.sh failed with a comment and a socket path in ~/.zprofile"; }
echo "$doctor_out" >>"$LOG"
grep -qF 'ssh-agent in ~/.zprofile' <<<"$doctor_out" &&
  die "doctor.sh warned about a comment or a socket path in ~/.zprofile"
# shellcheck disable=SC2016  # literal lines for ~/.zprofile
echo 'eval "$(ssh-agent -s)" > /dev/null 2>&1' >>"$HOME/.zprofile"
# One real agent for doctor to count. Its socket goes under its HOME, and the
# temp HOME's path is too long for a socket.
agent_home="$(mktemp -d /tmp/fresh-home-agent.XXXXXX)"
agent_env="$(HOME="$agent_home" ssh-agent -s)" || die "ssh-agent didn't start"
eval "$agent_env" >/dev/null
doctor_rc=0
doctor_out="$("$REPO_DIR/doctor.sh" 2>&1)" || doctor_rc=$?
eval "$(ssh-agent -k)" >/dev/null
rm -rf "$agent_home" "$HOME/.zprofile"
echo "$doctor_out" >>"$LOG"
((doctor_rc == 0)) || die "doctor.sh failed with ssh-agent in ~/.zprofile"
grep -qF 'ssh-agent in ~/.zprofile' <<<"$doctor_out" ||
  die "doctor.sh didn't warn about ssh-agent in ~/.zprofile"
counted='[1-9][0-9]* running now'
[[ "$doctor_out" =~ $counted ]] || die "doctor.sh didn't count the running ssh-agent"
grep -qF 'launchd provides an agent on demand' <<<"$doctor_out" ||
  die "doctor.sh didn't say how to fix ssh-agent in ~/.zprofile"

echo "doctor.sh with an nvim plugin missing (should fail, naming it)"
mv "$HOME/.local/share/nvim/lazy/base46" "$HOME/base46.away"
doctor_rc=0
doctor_out="$("$REPO_DIR/doctor.sh" 2>&1)" || doctor_rc=$?
mv "$HOME/base46.away" "$HOME/.local/share/nvim/lazy/base46"
echo "$doctor_out" >>"$LOG"
((doctor_rc != 0)) || die "doctor.sh passed with an nvim plugin missing"
grep -F 'nvim plugins missing' <<<"$doctor_out" | grep -qF base46 ||
  die "doctor.sh didn't name the missing nvim plugin"

echo "update.sh for real, with a brew that only records upgrades"
load_brew
# shellcheck disable=SC2016  # for the fake brew
printf '#!/bin/sh\ncase "$1" in upgrade) echo "$*" >>"%s/calls" ;; *) exec %s "$@" ;; esac\n' \
  "$BREW_SHIM_DIR" "$(command -v brew)" >"$BREW_SHIM_DIR/brew"
rm -f "$BREW_SHIM_DIR/calls"
# A changed tracked file, in a plugin lazy would otherwise report as failed.
changed_plugin="$HOME/.local/share/nvim/lazy/base46"
echo '-- changed' >>"$changed_plugin/lua/base46/init.lua"
update_rc=0
update_out="$(PATH="$BREW_SHIM_DIR:$PATH" "$REPO_DIR/update.sh" 2>&1)" || update_rc=$?
git -C "$changed_plugin" checkout -q lua/base46/init.lua
echo "$update_out" >>"$LOG"
((update_rc == 0)) || die "update.sh failed:"$'\n'"$update_out"
[[ "$update_out" == *"base46: skipped"* ]] || die "update.sh didn't skip the changed nvim plugin: $update_out"
[[ -s "$BREW_SHIM_DIR/calls" ]] || die "update.sh ran no brew upgrade"
[[ "$update_out" == *"catppuccin/tmux: skipped"* ]] || die "update.sh didn't skip catppuccin: $update_out"
if grep -vE "^upgrade ($(printf '%s\n' "${FORMULAE[@]}" | cut -d: -f1 | paste -sd '|' -))\$" "$BREW_SHIM_DIR/calls"; then
  die "update.sh upgraded something outside FORMULAE"
fi
[[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]] || die "update.sh changed the repo: $(git -C "$REPO_DIR" status --porcelain)"
"$REPO_DIR/doctor.sh" >>"$LOG" 2>&1 || die "doctor.sh failed after update.sh"

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

# izsh <PATH> <command>: runs the command in an interactive zsh.
izsh() { env -i HOME="$HOME" PATH="$1" TERM=xterm-256color zsh -i -c "$2" 2>&1; }

echo "zsh sets EDITOR and VISUAL, keeps PATH unique and in order, and stays on emacs"
# shellcheck disable=SC2016  # $EDITOR, $VISUAL and $path are for the inner zsh
read_editors='print -r -- "[$EDITOR][$VISUAL]"' read_path='print -rl -- $path'
editors="$(izsh "$PATH" "$read_editors")"
[[ "$editors" == '[nvim][nvim]' ]] || die "zsh has EDITOR and VISUAL as $editors, not nvim"
path_order="$(izsh "/p/a:/p/b:/p/a:/p/c:$PATH" "$read_path")"
[[ -z "$(sort <<<"$path_order" | uniq -d)" ]] || die "zsh's PATH has duplicates:"$'\n'"$path_order"
[[ "$(grep '^/p/' <<<"$path_order" | tr '\n' ' ')" == '/p/a /p/b /p/c ' ]] || die "zsh changed PATH's order:"$'\n'"$path_order"
outer_path="$(izsh "$PATH" "$read_path")"
# shellcheck disable=SC2016  # for the inner zsh
nested_path="$(izsh "$PATH" 'zsh -i -c "print -rl -- \$path"')"
[[ "$nested_path" == "$outer_path" ]] || die "a nested zsh has a different PATH:"$'\n'"$nested_path"
keymap="$(izsh "$PATH" "zsh -i -c 'bindkey -lL main'")"
[[ "$keymap" == 'bindkey -A emacs main' ]] || die "a nested zsh, with EDITOR inherited, isn't on the emacs keymap: $keymap"
mv "$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh.away"
keymap="$(izsh "$PATH" "zsh -i -c 'bindkey -lL main'")"
mv "$HOME/.oh-my-zsh.away" "$HOME/.oh-my-zsh"
[[ "$keymap" == *'bindkey -A emacs main' ]] || die "without Oh My Zsh, a nested zsh isn't on the emacs keymap: $keymap"

echo "the per-machine file overrides EDITOR and VISUAL, and its PATH entries stay unique"
# shellcheck disable=SC2016  # literal lines for ~/.zshrc.local
printf '%s\n' 'export EDITOR=vi VISUAL=vi' 'export PATH="/p/b:$PATH"' >>"$HOME/.zshrc.local"
editors="$(izsh "$PATH" "$read_editors")"
[[ "$editors" == '[vi][vi]' ]] || die "the per-machine file didn't override EDITOR and VISUAL: $editors"
path_order="$(izsh "/p/a:/p/b:$PATH" "$read_path")"
[[ -z "$(sort <<<"$path_order" | uniq -d)" ]] || die "an entry from the per-machine file duplicated PATH:"$'\n'"$path_order"
printf '%s\n' "$zshrc_local" >"$HOME/.zshrc.local"

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

echo "Ghostty config and every Ghostty extra are valid"
for f in "$HOME/.config/ghostty/config" "$REPO_DIR"/ghostty/extras/*; do
  "$(ghostty_app)/Contents/MacOS/ghostty" +validate-config --config-file="$f" >>"$LOG" 2>&1 ||
    die "Ghostty reports errors in ${f/#$HOME/~}"
done

echo "Ghostty reads the shared config's window settings"
ghostty_expect "shared config" window-decoration none
ghostty_expect "shared config" macos-window-shadow false
ghostty_expect "shared config" macos-titlebar-style hidden
ghostty_expect "shared config" macos-option-as-alt left

echo "every extra turned on with its README line"
for f in "$REPO_DIR"/*/extras/*; do turn_on_extra "${f#"$REPO_DIR"/}"; done
ghostty_expect window-frame.conf window-decoration auto
ghostty_expect window-frame.conf macos-window-shadow true
ghostty_expect window-frame.conf macos-titlebar-style transparent
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
rm "$HOME/.tmux.local.conf" "$HOME/.config/ghostty/local"
printf '%s\n' "$zshrc_local" >"$HOME/.zshrc.local"

echo "tmux extra missing from the repo"
# shellcheck disable=SC2016  # a literal tmux line
echo 'source-file "$DOTFILES/tmux/extras/no-such-extra.conf"' >"$HOME/.tmux.local.conf"
"$REPO_DIR/doctor.sh" >>"$LOG" 2>&1 && die "doctor.sh passed with a missing tmux extra"
rm "$HOME/.tmux.local.conf"

echo "real repo's working tree unchanged"
# A commit mid-run also changes repo_state, so name it rather than blame the run.
[[ "$(git -C "$REAL_REPO_DIR" rev-parse HEAD)" == "$head_before" ]] ||
  die "HEAD moved during the run; rerun with the repo untouched"
repo_after="$(repo_state)"
changed="$(comm -3 <(sort <<<"$repo_before") <(sort <<<"$repo_after") | sed -e '/^$/d' -e $'s/^\t//' | cut -f1 | sort -u)"
[[ -z "$changed" ]] || die "the run changed the real repo at $REAL_REPO_DIR:"$'\n'"$changed"

echo "PASS"
