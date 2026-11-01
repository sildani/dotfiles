#!/usr/bin/env bash
# Read-only health check: what's installed, what's linked, and which languages
# are set up. Changes nothing. Exits non-zero if something is broken (✗);
# warnings (!), such as a tool below its minimum, and language status never
# fail it.
# --diff instead shows how each config file differs from what install.sh
# would put there, and how many backed-up originals differ from the repo
# (--diff --backups shows those diffs too); it exits non-zero only if a diff
# can't run.
set -uo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

failures=0
broken() { fail "$1"; failures=$((failures + 1)); }

load_brew || true

check_tools() {
  section "Tools"
  if command -v brew >/dev/null; then
    ok "brew ($(brew --prefix))"
  else
    broken "brew not found"
    hint "see install.sh output for the install command"
  fi

  local entry formula cmd min version
  for entry in "${FORMULAE[@]}"; do
    IFS=: read -r formula cmd min <<<"$entry"
    if ! command -v "$cmd" >/dev/null; then
      broken "$cmd missing"
      hint "run ./install.sh (or: brew install $formula)"
      continue
    fi
    version="$(tool_version "$cmd")"
    if [[ -n "$min" ]] && ! version_ge "$version" "$min"; then
      warn "$cmd $version ($(tool_source "$cmd")) is older than $min"
      hint "re-run ./install.sh if brew installed it, otherwise upgrade it the way it was installed"
    else
      ok "$cmd $version ($(tool_source "$cmd"))${min:+, needs ≥ $min}"
    fi
  done

  if ghostty_app >/dev/null; then
    ok "Ghostty ($(ghostty_app))"
  else
    broken "Ghostty not found"
    hint "brew install --cask ghostty"
  fi

  if hurmit_font_installed; then
    ok "Hurmit Nerd Font"
  else
    broken "Hurmit Nerd Font not found"
    hint "brew install --cask font-hurmit-nerd-font"
  fi

  if command -v gh >/dev/null; then
    local account
    account="$(gh auth status --active 2>/dev/null | sed -nE 's/.*Logged in to ([^ ]+) account ([^ ]+).*/\2@\1/p' | head -1)"
    info "gh account: ${account:-not logged in} (informational; this repo never changes it)"
  fi

}

# The account's login shell, not $SHELL, which a parent process can set.
check_shell() {
  section "Shell"
  local shell
  shell="$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | sed -n 's/^UserShell: //p')"
  if [[ "$shell" == */zsh ]]; then
    ok "login shell is zsh ($shell)"
  else
    warn "login shell is ${shell:-unknown}, so ~/.zshrc isn't used"
    hint "chsh -s /bin/zsh"
  fi
  zprofile_ssh_agent
}

# ~/.zprofile runs in every login shell, tmux panes included, and an ssh-agent
# started there outlives its shell, so they pile up until a reboot. A guarded
# start may not, hence "can". The launchd agent runs as ssh-agent -l, which
# the pattern spares.
zprofile_ssh_agent() {
  grep -Eq '^[^#]*ssh-agent( |\)|`|$)' "$HOME/.zprofile" 2>/dev/null || return 0
  local leftovers='(^|/)ssh-agent( -s)?$' running
  running="$(pgrep -f "$leftovers" | wc -l | tr -d ' ')"
  warn "ssh-agent in ~/.zprofile can leave one per login shell ($running running now)"  # fresh-home.sh greps for "ssh-agent in ~/.zprofile<count> running now"
  hint "delete those lines (launchd provides an agent on demand), then stop the leftovers, and any keys loaded in them: pkill -f '$leftovers'"  # fresh-home.sh greps for "launchd provides an agent on demand"
}

# plist_value <plist text> <key path>: fails if the key isn't there. An array
# gives its length.
plist_value() { plutil -extract "$2" raw -o - - <<<"$1" 2>/dev/null; }

# Enabled input sources, leaving out Non Keyboard Input Method entries such as
# emoji.
input_source_count() {
  local plist count i kept=0
  plist="$(defaults export com.apple.HIToolbox - 2>/dev/null)"
  count="$(plist_value "$plist" AppleEnabledInputSources)" || count=0
  for ((i = 0; i < count; i++)); do
    [[ "$(plist_value "$plist" "AppleEnabledInputSources.$i.InputSourceKind")" == "Non Keyboard Input Method" ]] || kept=$((kept + 1))
  done
  echo "$kept"
}

# Hotkey 60, "select previous input source", is on and Ctrl-Space. Both are the
# default, so an absent key counts.
previous_source_is_ctrl_space() {
  local ctrl_space="32 49 262144" key=AppleSymbolicHotKeys.60
  local plist enabled i shortcut=""
  plist="$(defaults export com.apple.symbolichotkeys - 2>/dev/null)"
  enabled="$(plist_value "$plist" "$key.enabled")" || enabled=true
  [[ "$enabled" == true ]] || return 1
  for i in 0 1 2; do
    shortcut+="$(plist_value "$plist" "$key.value.parameters.$i") "
  done
  [[ -z "${shortcut// /}" || "$shortcut" == "$ctrl_space " ]]
}

# With more than one input source, the hotkey takes Ctrl-Space before tmux gets
# its prefix.
check_ctrl_space() {
  section "macOS"
  if (($(input_source_count) > 1)) && previous_source_is_ctrl_space; then
    warn "macOS takes Ctrl-Space, the tmux prefix, to switch input sources"  # doctor-warnings.sh greps for "macOS takes Ctrl-Space"
    hint "System Settings > Keyboard > Keyboard Shortcuts > Input Sources: turn off or change \"Select the previous input source\""
  else
    ok "macOS leaves Ctrl-Space to tmux"
  fi
}

check_links() {
  section "Config links"
  local entry src dest
  for entry in "${LINKS[@]}"; do
    src="$REPO_DIR/${entry%%:*}"
    dest="${entry#*:}"
    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
      ok "${dest/#$HOME/~}"
    elif [[ -L "$dest" ]]; then
      broken "${dest/#$HOME/~} links to $(readlink "$dest"), not this repo"
      hint "run ./install.sh (it backs up the old target first); ./doctor.sh --diff shows what it would replace"
    elif [[ -e "$dest" ]]; then
      broken "${dest/#$HOME/~} is a regular file/dir, not a link to the repo"
      hint "run ./install.sh (it backs up the old one first); ./doctor.sh --diff shows what it would replace"
    else
      broken "${dest/#$HOME/~} missing"
      hint "run ./install.sh"
    fi
  done

  local f
  for f in "${GHOSTTY_LIBRARY_FILES[@]}"; do
    if [[ -e "$f" ]]; then
      warn "${f/#$HOME/~} exists and overrides the repo's Ghostty config"
      hint "move its settings into ~/.config/ghostty/local, then delete it (or re-run ./install.sh)"
    fi
  done

  local local_file
  for local_file in "${LOCAL_FILES[@]}"; do
    [[ -e "$local_file" ]] && info "per-machine override in use: ${local_file/#$HOME/~}"
  done
  extras_cue

  # Opt-in snippets from <tool>/extras/ that the tool's per-machine file sources.
  local pair tool file extra
  for pair in "${EXTRAS_HOSTS[@]}"; do
    tool="${pair%%:*}" file="${pair#*:}"
    [[ -f "$file" ]] || continue
    while read -r extra; do
      if [[ -f "$REPO_DIR/$extra" ]]; then
        info "$tool extra on: ${extra##*/}"  # fresh-home.sh greps for "<tool> extra on: <name>"
      else
        broken "${file/#$HOME/~} sources $extra, which isn't in the repo"
        hint "pick one from $REPO_DIR/$tool/extras/ or remove the line"
      fi
    done < <(grep -v '^[[:space:]]*#' "$file" | grep -oE "$tool/extras/[^[:space:]\"']+")
  done
}

# tmux-continuum skips auto-save and auto-restore while another tmux server
# runs (a test's or an agent's -L socket). A server detaches, so its parent is
# PID 1; a client's isn't.
stray_tmux_servers() {
  local ppid args words word flags flag socket next strays=()
  while read -r ppid args; do
    [[ "$ppid" == 1 ]] || continue
    read -r -a words <<<"$args"
    [[ "${words[0]##*/}" == tmux ]] || continue
    # tmux's own flags, as getopt reads them (-2L name, -Lname, -L name), up
    # to the command; c f L S T take an argument.
    socket=default next=""
    for word in "${words[@]:1}"; do
      if [[ -n "$next" ]]; then
        [[ "$next" == [LS] ]] && socket="$word"
        next=""
        continue
      fi
      [[ "$word" == -?* ]] || break
      flags="${word#-}"
      while [[ -n "$flags" ]]; do
        flag="${flags:0:1}" flags="${flags:1}"
        [[ "$flag" == [cfLST] ]] || continue
        if [[ -z "$flags" ]]; then
          next="$flag"
        elif [[ "$flag" == [LS] ]]; then
          socket="$flags"
        fi
        break
      done
    done
    [[ "${socket##*/}" == default ]] || strays+=("$socket")
  done < <(ps -axo ppid=,args=)
  ((${#strays[@]})) || return 0
  warn "tmux servers besides the default one are running (${strays[*]}): continuum's auto-save and auto-restore are off"  # fresh-home.sh greps for "tmux servers besides the default one are running"
  hint "stop each with: tmux -L <name> kill-server (tmux -S <path> kill-server for a path)"
}

check_origin() {
  section "Repo"
  case "$(repo_origin_state)" in
    current) ok "up to date with origin" ;;
    behind)
      warn "this clone is behind origin"  # doctor-warnings.sh greps for "behind origin"
      hint "$(pull_command)"
      ;;
    *) info "couldn't reach origin, so this clone wasn't compared with it" ;;  # doctor-warnings.sh greps for "couldn't reach origin"
  esac
}

check_plugins() {
  section "Plugins"
  if [[ -d "$ZSH_DIR" ]]; then
    ok "Oh My Zsh"
  else
    broken "Oh My Zsh not installed (${ZSH_DIR/#$HOME/~})"
    hint "run ./install.sh"
  fi

  if [[ -d "$TPM_DIR" ]]; then
    local repo missing=()
    while read -r repo _; do
      [[ -d "$HOME/.tmux/plugins/${repo##*/}" ]] || missing+=("${repo##*/}")
    done < <(tmux_plugins)
    if ((${#missing[@]})); then
      broken "tmux plugins missing: ${missing[*]}"
      hint "run ./install.sh (or prefix + I inside tmux)"
    else
      ok "TPM and all tmux plugins"
    fi
  else
    broken "TPM not installed"
    hint "run ./install.sh"
  fi
  stray_tmux_servers

  local name missing=()
  if [[ -f "$NVIM_LOCK" ]]; then
    while read -r name _; do
      [[ -d "$NVIM_DATA/lazy/$name" ]] || missing+=("$name")
    done < <(nvim_lock_plugins)
    if ((${#missing[@]})); then
      broken "nvim plugins missing: ${missing[*]}"  # fresh-home.sh greps for "nvim plugins missing"
      hint "run ./install.sh (or :Lazy restore in nvim)"
    else
      ok "all nvim plugins in this machine's lockfile"
    fi
  else
    warn "no nvim lockfile at ${NVIM_LOCK/#$HOME/~}, so nvim plugins weren't checked"
    hint "run ./install.sh"
  fi

  missing=()
  while read -r name; do
    [[ -e "$TS_PARSERS/$name.so" ]] || missing+=("$name")
  done < <(wanted_parsers)
  if ((${#missing[@]})); then
    broken "treesitter parsers missing: ${missing[*]}"
    hint "run ./install.sh (or :TSInstallAll in nvim)"
  else
    ok "treesitter parsers: $(wanted_parsers | tr '\n' ' ')"
  fi
}

# --diff: each config install.sh manages, compared with the repo copy that would
# replace it. Diffs run machine -> repo, so + lines are what the repo installs.
DIFF_FLAGS=(-ru)
# Older macOS ships a diff without --color.
[[ -t 1 ]] && diff --color=always /dev/null /dev/null >/dev/null 2>&1 && DIFF_FLAGS+=(--color=always)
# Where install.sh's backups land, as repo path : machine path (LINKS plus
# Ghostty's Library config).
BACKUP_TARGETS=("${LINKS[@]}")
for f in "${GHOSTTY_LIBRARY_FILES[@]}"; do BACKUP_TARGETS+=("ghostty/config:$f"); done

same_as_repo() { diff -rq "$1" "$2" >/dev/null 2>&1; }

# A diff that can't run (unreadable file, file vs directory) is a problem.
show_diff() {
  diff "${DIFF_FLAGS[@]}" "$1" "$2"
  (($? < 2)) || broken "couldn't compare ${1/#$HOME/~} with ${2/#$HOME/~}"
}

diff_configs() {
  section "What install.sh would replace (- this machine, + the repo)"
  local entry src dest what
  for entry in "${LINKS[@]}"; do
    src="$REPO_DIR/${entry%%:*}" dest="${entry#*:}"
    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
      ok "${dest/#$HOME/~} already links to the repo"  # fresh-home.sh greps for "already links to the repo"
      continue
    elif [[ -L "$dest" && ! -e "$dest" ]]; then
      warn "${dest/#$HOME/~} is a broken link to $(readlink "$dest"); would be backed up and linked"  # fresh-home.sh greps for "would be "
    elif [[ -e "$dest" ]]; then
      what="is a file"
      [[ -d "$dest" ]] && what="is a directory"
      [[ -L "$dest" ]] && what="links to $(readlink "$dest")"
      if same_as_repo "$dest" "$src"; then
        info "${dest/#$HOME/~} $what with the repo's content; would be backed up and linked"  # fresh-home.sh greps for "would be "
      else
        warn "${dest/#$HOME/~} $what; would be backed up and replaced:"  # fresh-home.sh greps for "would be "
        show_diff "$dest" "$src"
      fi
    else
      info "${dest/#$HOME/~} missing, would be created"  # fresh-home.sh greps for "would be "
      continue
    fi
    if [[ "$dest" == "$HOME/.zshrc" && -f "$dest" ]]; then
      if [[ -e "$HOME/.zshrc.local" ]]; then
        hint "not copied to ~/.zshrc.local, which already exists; move what you need there by hand"  # fresh-home.sh doesn't grep for this
      else
        hint "${dest/#$HOME/~} would also be copied to ~/.zshrc.local (its Oh My Zsh load commented out) so this machine's setup keeps working"  # fresh-home.sh greps for "would also be copied to ~/.zshrc.local"
      fi
    fi
  done

  local f
  for f in "${GHOSTTY_LIBRARY_FILES[@]}"; do
    [[ -e "$f" ]] || continue
    warn "${f/#$HOME/~} overrides the repo's Ghostty config; would be backed up and removed:"  # fresh-home.sh greps for "would be "
    show_diff "$f" "$REPO_DIR/ghostty/config"
  done
}

# Originals install.sh moved to ~/.dotfiles-backup/<time>/ that the repo's
# config doesn't match: settings this machine may still want in its
# per-machine files. They never come to match, so they're summed up in one
# line unless $1 is true (--backups).
diff_backups() {
  local full="$1"
  section "Backed-up originals that differ from the repo"
  local dir entry src saved count=0 newest=""
  for dir in "$HOME"/.dotfiles-backup/*/; do
    [[ -d "$dir" ]] || continue
    for entry in "${BACKUP_TARGETS[@]}"; do
      src="$REPO_DIR/${entry%%:*}" saved="$dir${entry#*:"$HOME"/}"
      [[ -e "$saved" ]] || continue
      same_as_repo "$saved" "$src" && continue
      count=$((count + 1)) newest="${dir%/}"
      $full || continue
      warn "${saved/#$HOME/~}:"
      show_diff "$saved" "$src"
    done
  done
  if ((count == 0)); then
    ok "none"
  elif ! $full; then
    local differ="originals differ"
    ((count == 1)) && differ="original differs"
    info "$count backed-up $differ from the repo (newest: ${newest##*/})"  # fresh-home.sh greps for "backed-up originals differ from the repo (newest: "
    hint "see the diffs: ./doctor.sh --diff --backups"
  fi
}

mason_has()   { [[ -d "$MASON_PKGS/$1" ]]; }
parser_has()  { [[ -e "$TS_PARSERS/$1.so" ]]; }
lsp_enabled() { grep -Eq "^[[:space:]]*\"$1\"," "$REPO_DIR/nvim/lua/configs/lspconfig.lua"; }

# language_status <Name> <anchor> <runtime found?> <runtime label> <parser> <server> <mason pkgs...>
language_status() {
  local lang="$1" anchor="$2" runtime_ok="$3" runtime="$4" parser="$5" server="$6"
  shift 6
  local todo=() pkg
  $runtime_ok || todo+=("install $runtime")
  for pkg in "$@"; do mason_has "$pkg" || todo+=(":MasonInstall $pkg"); done
  parser_has "$parser" || todo+=("enable the \"$parser\" parser")
  lsp_enabled "$server" || todo+=("enable \"$server\" in lspconfig.lua")

  if ((${#todo[@]} == 0)); then
    ok "$lang: set up"
  elif ((${#todo[@]} == $# + 3)); then
    info "$lang: not set up (on purpose until you need it)"
    hint "LANGUAGES.md#$anchor"
  elif $runtime_ok && ! mason_has "$server"; then
    info "$lang: $runtime found, no LSP yet"
    hint "LANGUAGES.md#$anchor"
  else
    local joined
    joined="$(printf '%s; ' "${todo[@]}")"
    warn "$lang: partly set up; still to do: ${joined%; }"
    hint "LANGUAGES.md#$anchor"
  fi
}

check_languages() {
  section "Languages (manual, see LANGUAGES.md)"
  local java=false python=false go=false
  /usr/libexec/java_home -v 21+ >/dev/null 2>&1 && java=true
  command -v python3 >/dev/null && command -v node >/dev/null && python=true
  command -v go >/dev/null && go=true

  language_status Java java "$java" "a JDK 21+" java jdtls jdtls
  language_status Python python "$python" "python3 + node" python basedpyright basedpyright ruff
  language_status Go go "$go" "go" go gopls gopls goimports gofumpt
}

case "${1:-} ${2:-}" in
  " ") ;;
  "--diff " | "--diff --backups")
    diff_configs
    diff_backups "$([[ "${2:-}" == --backups ]] && echo true || echo false)"
    exit $((failures > 0))
    ;;
  *)
    echo "usage: doctor.sh [--diff [--backups]]" >&2
    exit 2
    ;;
esac

check_tools
check_shell
check_ctrl_space
check_links
check_origin
check_plugins
check_languages

echo
if ((failures)); then
  printf '%s%d problem(s) found.%s Fix hints are under each ✗ line.\n' "$C_RED" "$failures" "$C_OFF"
  exit 1
fi
printf '%sAll good.%s\n' "$C_GREEN" "$C_OFF"
