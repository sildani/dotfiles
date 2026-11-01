#!/usr/bin/env bash
# Brings this Mac up to date, with no repo change needed: the brew formulae in
# FORMULAE, Oh My Zsh, tmux plugins, nvim plugins (writing this Mac's own
# lockfile) and treesitter parsers. Never runs git pull. Ghostty, the font and
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

load_brew || true

step_failed() {
  fail "$1 failed"
  hint "details: ${LOG/#$HOME/~}"
  failures=$((failures + 1))
}

run() { "$@" >>"$LOG" 2>&1; }

# report <name> <old> <new> <what to restart if it changed>
report() {
  if [[ "$2" == "$3" ]]; then
    ok "$1 $2 (up to date)"
    return
  fi
  ok "$1 $2 → $3"
  [[ -z "$4" || ",$to_restart," == *",$4,"* ]] || to_restart+="${to_restart:+,}$4"
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
    if run brew upgrade "$formula"; then
      case "$cmd" in
        tmux) report "$cmd" "$old" "$(tool_version "$cmd")" "tmux (tmux kill-server)" ;;
        nvim) report "$cmd" "$old" "$(tool_version "$cmd")" nvim ;;
        *) report "$cmd" "$old" "$(tool_version "$cmd")" "" ;;
      esac
    else
      step_failed "$cmd: brew upgrade"
    fi
  done
}

# update_clone <name> <dir> <what to restart> <move>: <move> takes the dir and
# brings the clone up. A change to a tracked file skips it; reset --hard would
# lose the change. Untracked files are left alone.
update_clone() {
  local name="$1" dir="$2" restart="$3" move="$4" old
  if [[ ! -d "$dir/.git" ]]; then
    info "$name: skipped, not installed (run ./install.sh)"
    return
  fi
  if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    warn "$name: skipped, its tracked files have local changes"
    return
  fi
  old="$(git -C "$dir" rev-parse --short HEAD)"
  if "$move" "$dir"; then
    report "$name" "$old" "$(git -C "$dir" rev-parse --short HEAD)" "$restart"
  else
    step_failed "$name: update"
  fi
}

# install.sh's clone is shallow, which a pull can't move.
move_shallow() {
  run git -C "$1" fetch --depth=1 origin HEAD && run git -C "$1" reset --hard FETCH_HEAD
}

# Not TPM's update-all: it runs git pull, which fails on a detached checkout.
move_forward() {
  run git -C "$1" fetch origin HEAD &&
    run git -C "$1" merge --ff-only FETCH_HEAD &&
    run git -C "$1" submodule update --init --recursive
}

update_oh_my_zsh() {
  section "Oh My Zsh"
  update_clone "Oh My Zsh" "$ZSH_DIR" "a new shell" move_shallow
}

update_tmux_plugins() {
  section "tmux plugins"
  local repo ref
  while read -r repo ref; do
    if [[ -n "$ref" ]]; then
      info "$repo: skipped, pinned to $ref in tmux.conf"
    else
      update_clone "${repo##*/}" "$HOME/.tmux/plugins/${repo##*/}" "tmux (tmux kill-server)" move_forward
    fi
  done < <(tmux_plugins)
}

update_nvim() {
  section "nvim plugins and parsers"
  if ! command -v nvim >/dev/null; then
    info "nvim: skipped, not installed (run ./install.sh)"
    return
  fi
  local before name commit old changed=false parsers_before
  before="$(nvim_lock_plugins)"
  # Headless lazy reports a failed plugin only in its UI.
  if run nvim --headless \
    "+lua local lazy = require('lazy'); lazy.update({ wait = true, show = false }); for _, p in ipairs(lazy.plugins()) do if require('lazy.core.plugin').has_errors(p) then vim.cmd('1cquit') end end" \
    +qa; then
    while read -r name commit; do
      old="$(awk -v name="$name" '$1 == name { print $2 }' <<<"$before")"
      [[ "$old" == "$commit" ]] && continue
      report "$name" "${old:0:7}" "${commit:0:7}" nvim
      changed=true
    done < <(nvim_lock_plugins)
    $changed || ok "nvim plugins up to date"
  else
    step_failed "nvim plugins: update"
  fi

  parsers_before="$(ls -lT "$TS_PARSERS" 2>/dev/null)"
  if run nvim --headless \
    "+lua require('lazy').load({ plugins = { 'nvim-treesitter' } })" \
    "+lua require('nvim-treesitter').update():wait(300000)" \
    +qa; then
    if [[ "$(ls -lT "$TS_PARSERS" 2>/dev/null)" == "$parsers_before" ]]; then
      ok "treesitter parsers up to date"
    else
      report "treesitter parsers" old new nvim
    fi
  else
    step_failed "treesitter parsers: update"
  fi
}

update_formulae
update_oh_my_zsh
update_tmux_plugins
update_nvim

mkdir -p "$(dirname "$UPDATE_STAMP")"
touch "$UPDATE_STAMP"

echo
if [[ "$(repo_origin_state)" == behind ]]; then
  info "this clone is behind origin, which update.sh leaves alone: git -C ${REPO_DIR/#$HOME/~} pull && ./install.sh"
fi
if [[ -n "$to_restart" ]]; then
  info "restart to pick this up: ${to_restart//,/, }"
fi
if ((failures)); then
  printf '%s%d step(s) failed.%s\n' "$C_RED" "$failures" "$C_OFF"
  exit 1
fi
