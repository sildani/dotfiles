#!/usr/bin/env bash
# Fast checks of how a Mac keeps itself current: runs the real update.sh, on
# stock bash, from a copy of the repo in an empty temp HOME. Homebrew, nvim and
# every tool are fakes on PATH that record their calls, and Oh My Zsh and the
# tmux plugins are clones of local repos, so nothing real is upgraded. Also
# checks that a brew tool below its minimum gets upgraded, and the shared
# zshrc's update reminder.
set -euo pipefail

REAL_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
unset TMUX TMUX_PANE TMUX_PLUGIN_MANAGER_PATH XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME DOTFILES SSH_AGENT_PID SSH_AUTH_SOCK
mkdir -p "$HOME"

# shellcheck source=lib/common.sh
source "$REAL_REPO_DIR/lib/common.sh"
copy_worktree "$REAL_REPO_DIR" "$TMP/repo"
# The copy's, so its REPO_DIR, and with it its tmux.conf, is the copy.
# shellcheck source=lib/common.sh
source "$TMP/repo/lib/common.sh"

failures=0
failed() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }
new_commit() {
  echo "$2" >>"$1/file"
  git -C "$1" add file
  git -C "$1" -c user.name=t -c user.email=t@localhost -c commit.gpgsign=false commit -q --no-verify -m "$2"
}
head_of() { git -C "$1" rev-parse HEAD; }

# upstream <name>: a repo to clone from, with one commit, on branch master.
upstream() {
  git init -q -b master "$TMP/upstream/$1"
  new_commit "$TMP/upstream/$1" first
}

# The repo's origin, one commit ahead of the copy.
git init -q --bare -b main "$TMP/origin.git"
git -C "$TMP/repo" branch -q -M main
git -C "$TMP/repo" remote add origin "$TMP/origin.git"
git -C "$TMP/repo" push -q origin main
git clone -q "$TMP/origin.git" "$TMP/other-clone"
new_commit "$TMP/other-clone" ahead
git -C "$TMP/other-clone" push -q origin HEAD:main

# Oh My Zsh, shallow as install.sh clones it, with an untracked file of its own.
upstream oh-my-zsh
git clone -q --depth=1 "file://$TMP/upstream/oh-my-zsh" "$ZSH_DIR"
mkdir "$ZSH_DIR/custom"
echo mine >"$ZSH_DIR/custom/mine.zsh"
new_commit "$TMP/upstream/oh-my-zsh" second

# Every tmux plugin in tmux.conf, with a newer commit upstream.
while read -r repo _; do
  name="${repo##*/}"
  upstream "$name"
  git clone -q "$TMP/upstream/$name" "$HOME/.tmux/plugins/$name"
  new_commit "$TMP/upstream/$name" second
done < <(tmux_plugins)
git -C "$HOME/.tmux/plugins/tmux" checkout -q --detach  # catppuccin, on its tag
echo 'changed' >>"$HOME/.tmux/plugins/tmux-yank/file"

# This Mac's nvim lockfile.
mkdir -p "$NVIM_STATE"
lock() { printf '{\n  "plugin-a": { "branch": "main", "commit": "%s" },\n  "plugin-b": { "branch": "main", "commit": "cccccccc" }\n}\n' "$1"; }
lock aaaaaaaa >"$NVIM_LOCK"

# Fake Homebrew: tools under its prefix, versions in $VERSIONS, calls in $CALLS.
export CALLS="$TMP/calls" VERSIONS="$TMP/versions" FAIL_FORMULA="" FAIL_NVIM="" REAL_GIT LOCK_FILE="$NVIM_LOCK"
REAL_GIT="$(command -v git)"
BREW="$TMP/homebrew"
mkdir -p "$BREW/bin" "$TMP/elsewhere" "$VERSIONS"
cat >"$BREW/bin/brew" <<SHIM
#!/bin/sh
echo "brew \$*" >>"\$CALLS"
case "\$1" in
  --prefix) echo "$BREW" ;;
  upgrade)
    [ "\$2" = "\$FAIL_FORMULA" ] && exit 1
    echo 2.0 >"\$VERSIONS/\$2" ;;
esac
SHIM
for entry in "${FORMULAE[@]}"; do
  IFS=: read -r formula cmd _ <<<"$entry"
  echo 1.0 >"$VERSIONS/$formula"
  dir="$BREW/bin"
  [[ "$cmd" == tree-sitter ]] && dir="$TMP/elsewhere"  # one tool brew didn't install
  # shellcheck disable=SC2016  # for the fake tool
  case "$cmd" in
    git) rest='echo "git $*" >>"$CALLS"; exec "$REAL_GIT" "$@"' ;;
    nvim) rest='echo "nvim $*" >>"$CALLS"
[ -z "$FAIL_NVIM" ] || exit 1
case "$*" in
  *nvim-treesitter*) ;;
  *) sed -i "" s/aaaaaaaa/bbbbbbbb/ "$LOCK_FILE" ;;
esac' ;;
    *) rest='' ;;
  esac
  # shellcheck disable=SC2016  # for the fake tool
  printf '#!/bin/sh\ncase "$1" in --version | -V) echo "version: $(cat "$VERSIONS/%s")"; exit 0 ;; esac\n%s\n' "$formula" "$rest" >"$dir/$cmd"
done
chmod +x "$BREW/bin/"* "$TMP/elsewhere/"*

update() { PATH="$BREW/bin:$TMP/elsewhere:$PATH" /bin/bash "$TMP/repo/update.sh" 2>&1; }

repo_head="$(head_of "$TMP/repo")"
catppuccin_head="$(head_of "$HOME/.tmux/plugins/tmux")"
yank_head="$(head_of "$HOME/.tmux/plugins/tmux-yank")"
mkdir -p "${UPDATE_STAMP%/*}"
touch -t 202001010000 "$UPDATE_STAMP"

echo "update.sh brings everything up"
rc=0
out="$(update)" || rc=$?
((rc == 0)) || failed "update.sh exited $rc:"$'\n'"$out"
want=""
for entry in "${FORMULAE[@]}"; do
  IFS=: read -r formula cmd _ <<<"$entry"
  [[ "$cmd" == tree-sitter ]] || want+="brew upgrade $formula"$'\n'
done
got="$(grep '^brew upgrade' "$CALLS" || true)"
[[ "$got"$'\n' == "$want" ]] || failed "brew should upgrade every FORMULAE tool it installed and nothing else, but ran:"$'\n'"$got"
[[ "$out" == *"rg 1.0 → 2.0"* ]] || failed "no old → new line for rg:"$'\n'"$out"
[[ "$out" == *"tree-sitter: skipped"* ]] || failed "no skip note for a tool brew didn't install:"$'\n'"$out"
[[ "$(head_of "$ZSH_DIR")" == "$(head_of "$TMP/upstream/oh-my-zsh")" ]] || failed "Oh My Zsh didn't move"
[[ "$(git -C "$ZSH_DIR" symbolic-ref --short HEAD)" == master ]] || failed "Oh My Zsh left its branch"
[[ "$(git -C "$ZSH_DIR" rev-parse --is-shallow-repository)" == true ]] || failed "Oh My Zsh's clone stopped being shallow"
[[ "$(cat "$ZSH_DIR/custom/mine.zsh")" == mine ]] || failed "Oh My Zsh's untracked custom/ file was touched"
sensible="$HOME/.tmux/plugins/tmux-sensible"
[[ "$(head_of "$sensible")" == "$(head_of "$TMP/upstream/tmux-sensible")" ]] || failed "tmux-sensible didn't move"
[[ "$(head_of "$HOME/.tmux/plugins/tmux")" == "$catppuccin_head" ]] || failed "catppuccin moved off its pin"
[[ "$out" == *"catppuccin/tmux: skipped"* ]] || failed "no skip note for catppuccin:"$'\n'"$out"
[[ "$(head_of "$HOME/.tmux/plugins/tmux-yank")" == "$yank_head" ]] || failed "tmux-yank moved despite its local change"
grep -q changed "$HOME/.tmux/plugins/tmux-yank/file" || failed "tmux-yank's local change was lost"
[[ "$out" == *"tmux-yank: skipped"* ]] || failed "no skip note for a changed plugin:"$'\n'"$out"
[[ "$out" == *"plugin-a aaaaaaa → bbbbbbb"* ]] || failed "no old → new line for an nvim plugin:"$'\n'"$out"
[[ "$out" != *"plugin-b "* ]] || failed "listed an nvim plugin that didn't change:"$'\n'"$out"
grep -q '^nvim .*nvim-treesitter' "$CALLS" || failed "update.sh didn't update the treesitter parsers"
[[ "$out" == *"behind origin"* ]] || failed "no note that the repo is behind origin:"$'\n'"$out"
[[ "$(head_of "$TMP/repo")" == "$repo_head" ]] || failed "update.sh moved the repo"
[[ -z "$(git -C "$TMP/repo" status --porcelain)" ]] || failed "update.sh dirtied the repo:"$'\n'"$(git -C "$TMP/repo" status --porcelain)"
grep -q '^git .*pull' "$CALLS" && failed "update.sh ran git pull"
[[ -z "$(find "$UPDATE_STAMP" -mtime +1)" ]] || failed "update.sh didn't restart the reminder's clock"
[[ "$out" == *"restart"* && "$out" == *"tmux kill-server"* && "$out" == *"new shell"* && "$out" == *"nvim"* ]] ||
  failed "no restart note for what changed:"$'\n'"$out"

echo "update.sh with nothing new says so, with no restart note"
out="$(update)" || failed "second update.sh run failed:"$'\n'"$out"
[[ "$out" != *"restart"* ]] || failed "restart note with nothing changed:"$'\n'"$out"

echo "update.sh restarts only what changed"
new_commit "$TMP/upstream/oh-my-zsh" third
out="$(update)" || failed "update.sh failed with a new Oh My Zsh commit:"$'\n'"$out"
[[ "$out" == *"new shell"* && "$out" != *"tmux kill-server"* ]] || failed "the restart note should name only a new shell:"$'\n'"$out"

echo "a failing step leaves the others to run, and fails at the end"
: >"$CALLS"
new_commit "$TMP/upstream/tmux-sensible" third
export FAIL_FORMULA=gh FAIL_NVIM=1
git -C "$ZSH_DIR" remote set-url origin "$TMP/no-such-repo"
rc=0
out="$(update)" || rc=$?
FAIL_FORMULA="" FAIL_NVIM=""
((rc != 0)) || failed "update.sh exited 0 with failing steps:"$'\n'"$out"
grep -q '^brew upgrade tmux' "$CALLS" || failed "a failed gh upgrade stopped the others"
[[ "$(head_of "$sensible")" == "$(head_of "$TMP/upstream/tmux-sensible")" ]] || failed "failed steps stopped the tmux plugins"
grep -q '^nvim .*nvim-treesitter' "$CALLS" || failed "failed steps stopped the treesitter parsers"
for name in gh 'Oh My Zsh' 'nvim plugins'; do
  [[ "$out" == *"$name"*failed* ]] || failed "no failure line for $name:"$'\n'"$out"
done

echo "a tool below its minimum gets brew upgrade only if brew installed it"
: >"$CALLS"
echo 1.0 >"$VERSIONS/tmux"
out="$(PATH="$BREW/bin:$TMP/elsewhere:$PATH" raise_to_minimum tmux tmux 3.5 2>&1)" || failed "raise_to_minimum failed: $out"
grep -q '^brew upgrade tmux$' "$CALLS" || failed "a brew tool below its minimum wasn't upgraded"
: >"$CALLS"
out="$(PATH="$BREW/bin:$TMP/elsewhere:$PATH" raise_to_minimum tree-sitter-cli tree-sitter 9 2>&1)" || failed "raise_to_minimum failed: $out"
grep -q '^brew upgrade' "$CALLS" && failed "ran brew upgrade on a tool brew didn't install"
[[ "$out" == *"older than 9"* ]] || failed "no warning for a non-brew tool below its minimum: $out"

echo "the update reminder"
ln -s "$TMP/repo/zsh/zshrc" "$HOME/.zshrc"
new_shell() { env -i HOME="$HOME" PATH="/usr/bin:/bin" TERM=xterm-256color zsh -i -c "${1:-true}" 2>/dev/null; }
days_old() { touch -t "$(date -v-"$1"d +%Y%m%d%H%M)" "$UPDATE_STAMP"; }
days_old 14
out="$(new_shell)"
# shellcheck disable=SC2016  # the reminder names it literally
[[ "$out" == *'"$DOTFILES/update.sh"'* ]] || failed "no reminder at 14 days: '$out'"
[[ "$(wc -l <<<"$out" | tr -d ' ')" == 1 ]] || failed "the reminder should be one line: $out"
out="$(new_shell)"
[[ -z "$out" ]] || failed "the reminder showed twice: $out"
days_old 13
out="$(new_shell)"
[[ -z "$out" ]] || failed "reminder at 13 days: $out"
rm "$UPDATE_STAMP"
out="$(new_shell)"
[[ -z "$out" && ! -e "$UPDATE_STAMP" ]] || failed "a missing timestamp should stay quiet and missing: $out"
touch -t 202001010000 "$UPDATE_STAMP"
out="$(env -i HOME="$HOME" PATH="/usr/bin:/bin" zsh -c true 2>/dev/null)"
[[ -z "$out" ]] || failed "a non-interactive shell printed: $out"
# shellcheck disable=SC2016  # for the inner zsh
mode="$(new_shell 'zstyle -s ":omz:update" mode m; print -r -- $m' | tail -1)"
[[ "$mode" == disabled ]] || failed "Oh My Zsh's update mode is '$mode', not disabled"

if ((failures)); then
  echo "updates: $failures failed" >&2
  exit 1
fi
echo "updates: ok"
