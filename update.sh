#!/usr/bin/env bash
# Brings this machine up to date, with no repo change needed: the brew formulae
# in FORMULAE, Oh My Zsh, tmux plugins, nvim plugins (writing its own lockfile)
# and treesitter parsers. Never runs git pull. Ghostty, the font and
# Rectangle stay out: they update themselves or rarely change, and upgrading a
# cask quits the app. A failing step doesn't stop the others; the script exits
# non-zero at the end.
set -uo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

LOG="$HOME/.dotfiles-update.log"
: >"$LOG"
failures=0
to_restart=""
RESTART_TMUX="tmux (tmux kill-server)"

load_brew || true

step_failed() {
  fail "$1 failed"
  hint "details: ${LOG/#$HOME/~}"
  failures=$((failures + 1))
}

run() { "$@" >>"$LOG" 2>&1; }

restart() { [[ ",$to_restart," == *",$1,"* ]] || to_restart+="${to_restart:+,}$1"; }

# report <name> <old> <new>: says whether it changed, and returns 0 if so.
report() {
  if [[ "$2" == "$3" ]]; then
    ok "$1 $2 (up to date)"
    return 1
  fi
  ok "$1 $2 → $3"
}

update_formulae() {
  section "Tools"
  local entry formula cmd source old
  for entry in "${FORMULAE[@]}"; do
    IFS=: read -r formula cmd _ <<<"$entry"
    if ! command -v "$cmd" >/dev/null; then
      info "$cmd: skipped, not installed (run ./install.sh)"
      continue
    fi
    source="$(tool_source "$cmd")"
    if [[ "$source" != brew ]]; then
      info "$cmd: skipped, brew didn't install it ($source)"
      continue
    fi
    old="$(tool_version "$cmd")"
    if ! run brew upgrade "$formula"; then
      step_failed "$cmd: brew upgrade"
    elif report "$cmd" "$old" "$(tool_version "$cmd")"; then
      case "$cmd" in
        tmux) restart "$RESTART_TMUX" ;;
        nvim) restart nvim ;;
      esac
    fi
  done
}

# update_clone <name> <dir> <what to restart> <move>: <move> takes the dir and
# brings the clone up. A change to a tracked file skips it; reset --hard would
# lose the change. Untracked files are left alone.
update_clone() {
  local name="$1" dir="$2" what="$3" move="$4" old
  if [[ ! -d "$dir/.git" ]]; then
    info "$name: skipped, not installed (run ./install.sh)"
    return
  fi
  if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    warn "$name: skipped, its tracked files have local changes"
    return
  fi
  old="$(git -C "$dir" rev-parse --short HEAD)"
  if ! "$move" "$dir"; then
    step_failed "$name: update"
  elif report "$name" "$old" "$(git -C "$dir" rev-parse --short HEAD)"; then
    restart "$what"
  fi
}

# install.sh's clone is shallow, which a pull can't move. Fetching by branch name
# keeps @{upstream} current, which update_oh_my_zsh checks.
move_shallow() {
  run git -C "$1" fetch --depth=1 origin "$(git -C "$1" symbolic-ref --short HEAD)" &&
    run git -C "$1" reset --hard FETCH_HEAD
}

# Not TPM's update-all: it runs git pull, which fails on a detached checkout.
move_forward() {
  run git -C "$1" fetch origin HEAD &&
    run git -C "$1" merge --ff-only FETCH_HEAD &&
    run git -C "$1" submodule update --init --recursive
}

update_oh_my_zsh() {
  section "Oh My Zsh"
  local ahead
  ahead="$(git -C "$ZSH_DIR" rev-list --count '@{upstream}..HEAD' 2>/dev/null)"
  if [[ -d "$ZSH_DIR/.git" && "$ahead" != 0 ]]; then
    warn "Oh My Zsh: skipped, it has local commits or isn't on its branch"
    return
  fi
  update_clone "Oh My Zsh" "$ZSH_DIR" "a new shell" move_shallow
}

update_tmux_plugins() {
  section "tmux plugins"
  local repo ref
  while read -r repo ref; do
    if [[ -n "$ref" ]]; then
      info "$repo: skipped, pinned to $ref in tmux.conf"
    else
      update_clone "${repo##*/}" "$HOME/.tmux/plugins/${repo##*/}" "$RESTART_TMUX" move_forward
    fi
  done < <(tmux_plugins)
}

update_nvim_plugins() {
  section "nvim plugins"
  local before dir name commit old skip="" updated=true changed=false
  before="$(nvim_lock_plugins)"
  for dir in "$NVIM_DATA"/lazy/*/; do
    [[ -d "$dir.git" && -n "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null)" ]] || continue
    name="$(basename "$dir")"
    warn "$name: skipped, its tracked files have local changes"
    skip+="$name "
  done
  SKIP_PLUGINS="$skip" run nvim --headless "+lua require('configs.update').plugins()" +qa || updated=false
  # Before the failure, if any: the plugins that did move are worth showing.
  if [[ -n "$before" ]]; then
    while read -r name commit; do
      old="$(awk -v name="$name" '$1 == name { print $2 }' <<<"$before")"
      [[ "$old" == "$commit" ]] && continue
      old="${old:-none}"
      ok "$name ${old:0:7} → ${commit:0:7}"
      changed=true
    done < <(nvim_lock_plugins)
  elif [[ -f "$NVIM_LOCK" ]]; then
    ok "nvim plugins updated (no earlier lockfile to compare with)"
    changed=true
  fi
  if $changed; then restart nvim; fi
  if ! $updated; then
    step_failed "nvim plugins: update"
  elif ! $changed; then
    ok "nvim plugins up to date"
  fi
}

update_parsers() {
  section "treesitter parsers"
  local before
  before="$(ls -lT "$TS_PARSERS" 2>/dev/null)"
  if ! run nvim --headless "+lua require('configs.update').parsers()" +qa; then
    step_failed "treesitter parsers: update"
  elif [[ "$(ls -lT "$TS_PARSERS" 2>/dev/null)" == "$before" ]]; then
    ok "treesitter parsers up to date"
  else
    ok "treesitter parsers updated"
    restart nvim
  fi
}

update_nvim() {
  if ! command -v nvim >/dev/null; then
    section "nvim plugins"
    info "nvim: skipped, not installed (run ./install.sh)"
    return
  fi
  update_nvim_plugins
  update_parsers
}

update_formulae
update_oh_my_zsh
update_tmux_plugins
update_nvim

mkdir -p "$(dirname "$UPDATE_STAMP")"
touch "$UPDATE_STAMP"

echo
if [[ "$(repo_origin_state)" == behind ]]; then
  info "this clone is behind origin, which update.sh leaves alone: $(pull_command)"
fi
if [[ -n "$to_restart" ]]; then
  info "restart to pick this up: ${to_restart//,/, }"
fi
if ((failures)); then
  printf '%s%d step(s) failed.%s\n' "$C_RED" "$failures" "$C_OFF"
  exit 1
fi
