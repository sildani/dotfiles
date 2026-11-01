#!/usr/bin/env bash
# Sets up zsh (Oh My Zsh), tmux, nvim and Ghostty from this repo, at the latest
# versions. Safe to re-run after `git pull`; update.sh keeps a machine current. Sets core.hooksPath in this
# clone; otherwise never touches git/gh config or auth. Never installs language
# support (see LANGUAGES.md).
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
nvim_config_replaced=false

backup() {
  mkdir -p "$BACKUP_DIR"
  local dest
  dest="$BACKUP_DIR/${1#"$HOME"/}"
  mkdir -p "$(dirname "$dest")"
  mv "$1" "$dest"
  info "moved ${1/#$HOME/~} -> ${dest/#$HOME/~}"  # fresh-home.sh greps for "moved "
}

# Appends a command's output to a log; shows the tail of it if the command fails.
run_logged() {
  local log="$1"
  shift
  if ! "$@" >>"$log" 2>&1; then
    fail "failed: $*"
    tail -20 "$log" | sed 's/^/    /'
    exit 1
  fi
}

confirm() {
  [[ -t 0 ]] || return 1
  local reply
  read -r -p "  $1 [y/N] " reply
  [[ "$reply" == [yY]* ]]
}

check_prereqs() {
  section "Prerequisites"
  [[ "$(uname -s)" == Darwin ]] || { fail "this setup is macOS-only"; exit 1; }

  if xcode-select -p >/dev/null 2>&1; then
    ok "Xcode Command Line Tools"
  else
    fail "Xcode Command Line Tools are missing (needed for git and treesitter's C compiler)"
    hint "run: xcode-select --install   then re-run this script"
    exit 1
  fi

  if load_brew; then
    ok "Homebrew ($(brew --prefix))"
  else
    fail "Homebrew is not installed"
    hint 'install it yourself, then re-run this script:'
    # shellcheck disable=SC2016  # printed for the user to run, not expanded here
    hint '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
  fi
}

# Installs only what's missing. An existing install stays as it is unless it's
# below its minimum; see raise_to_minimum.
install_tools() {
  section "Tools"
  local entry formula cmd min version
  for entry in "${FORMULAE[@]}"; do
    IFS=: read -r formula cmd min <<<"$entry"
    if ! command -v "$cmd" >/dev/null; then
      info "installing $formula"
      brew install "$formula"
      ok "$cmd $(tool_version "$cmd") (brew, just installed)"
      continue
    fi
    version="$(tool_version "$cmd")"
    if [[ -n "$min" ]] && ! version_ge "$version" "$min"; then
      raise_to_minimum "$formula" "$cmd" "$min"
    else
      ok "$cmd $version ($(tool_source "$cmd"))"
    fi
  done

  if ghostty_app >/dev/null; then
    ok "Ghostty ($(ghostty_app))"
  else
    info "installing ghostty"
    brew install --cask ghostty
  fi

  if hurmit_font_installed; then
    ok "Hurmit Nerd Font"
  else
    info "installing font-hurmit-nerd-font"
    brew install --cask font-hurmit-nerd-font
  fi

  install_rectangle
}

# A machine's own ~/.zshrc (PATH, nvm, ...) keeps working as ~/.zshrc.local,
# which the shared zshrc sources last. Skipped if ~/.zshrc.local exists. Only
# its own settings are kept, leaving out comments, blank lines and what the
# shared zshrc already does: Homebrew's shellenv, loading Oh My Zsh and the
# settings it reads only while loading (ZSH, ZSH_THEME, plugins, zstyle
# ':omz:...' and the template's others, listed in the case below; each with or
# without `export `, which the comparison with the shared zshrc ignores).
# ~/.zshrc.local loads after Oh My Zsh, too late for those settings, so it
# warns about any whose value differs from the shared zshrc's (plugins only for
# ones the shared list lacks). Settings Oh My Zsh reads at runtime, such as
# DISABLE_AUTO_TITLE, are kept.
migrate_zshrc() {
  local old="$HOME/.zshrc" new="$HOME/.zshrc.local" shared="$REPO_DIR/zsh/zshrc"
  [[ -f "$old" && ! -e "$new" ]] || return 0
  local shared_lines shared_plugins line trimmed setting in_plugins=false plugins="" p
  local kept=() lost=() missing=()
  shared_lines="$(sed 's/^export //' "$shared" | tr -d "\"'")"
  shared_plugins="$(sed -nE 's/^plugins=\((.*)\)$/\1/p' "$shared")"
  while IFS= read -r line || [[ -n "$line" ]]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    if ! $in_plugins && [[ "$trimmed" == 'plugins=('* ]]; then
      in_plugins=true
      trimmed="${trimmed#plugins=(}"
    fi
    if $in_plugins; then  # up to the closing ), which may be lines later
      [[ "$trimmed" == *")"* ]] && in_plugins=false
      plugins+=" ${trimmed%%[)#]*}"
      continue
    fi
    case "${trimmed#export }" in
      '' | '#'*) ;;
      'ZSH_THEME='* | 'ZSH='* | 'CASE_SENSITIVE='* | 'HYPHEN_INSENSITIVE='* | \
        'DISABLE_MAGIC_FUNCTIONS='* | 'DISABLE_LS_COLORS='* | 'ENABLE_CORRECTION='* | \
        'COMPLETION_WAITING_DOTS='* | 'HIST_STAMPS='* | 'ZSH_CUSTOM='* | \
        'ZSH_THEME_RANDOM_CANDIDATES='* | "zstyle ':omz:"* | 'zstyle ":omz:'*)
        setting="${trimmed%%[[:space:]]#*}"
        setting="${setting%"${setting##*[![:space:]]}"}"
        grep -qxF -- "$(tr -d "\"'" <<<"${setting#export }")" <<<"$shared_lines" || lost+=("$setting") ;;
      'source '*oh-my-zsh.sh* | '. '*oh-my-zsh.sh* | 'eval '*'brew shellenv'*) ;;
      *) kept+=("$line") ;;
    esac
  done <"$old"
  for p in $plugins; do
    [[ " $shared_plugins " == *" $p "* ]] || missing+=("$p")
  done
  ((${#missing[@]})) && lost+=("plugins ${missing[*]}")

  {
    echo "# Moved from ~/.zshrc by install.sh on $(date +%Y-%m-%d), without what the"
    echo "# shared zshrc already does. The full original is in"
    echo "#   ${BACKUP_DIR/#$HOME/~}/.zshrc"
    echo "# and Oh My Zsh's sample zshrc, with all its comments, is at ~/.zshrc.example."
    if ((${#kept[@]})); then printf '%s\n' "${kept[@]}"; fi
  } >"$new"
  info "copied ~/.zshrc to ~/.zshrc.local so this machine's shell setup keeps working"  # fresh-home.sh greps for "copied "
  if ((${#lost[@]})); then
    warn "Oh My Zsh settings the shared zshrc lacks weren't copied (~/.zshrc.local loads too late for them): ${lost[*]}"  # fresh-home.sh greps for "Oh My Zsh settings the shared zshrc lacks"
    hint "to keep them, add them to zsh/zshrc"
  fi
}

link_configs() {
  section "Config links"
  local entry src dest
  for entry in "${LINKS[@]}"; do
    src="$REPO_DIR/${entry%%:*}"
    dest="${entry#*:}"
    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
      ok "${dest/#$HOME/~} already links to the repo"  # fresh-home.sh doesn't grep for this
      continue
    fi
    if [[ -e "$dest" || -L "$dest" ]]; then
      [[ "$dest" == "$HOME/.zshrc" ]] && migrate_zshrc
      backup "$dest"
      [[ "$dest" == "$HOME/.config/nvim" ]] && nvim_config_replaced=true
    fi
    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
    ok "${dest/#$HOME/~} -> ${src/#$HOME/~}"  # fresh-home.sh greps for " -> "
  done

  local f
  for f in "${GHOSTTY_LIBRARY_FILES[@]}"; do
    if [[ -e "$f" ]]; then
      warn "Ghostty's Library config would override the repo's"
      backup "$f"
    fi
  done
}

# Plugins from an old nvim config confuse a fresh lazy install, so offer to
# move them aside. Only asked when an existing ~/.config/nvim was replaced.
maybe_reset_nvim_data() {
  $nvim_config_replaced || return 0
  local dirs=() d
  for d in "$NVIM_DATA" "$NVIM_STATE" "$NVIM_CACHE"; do
    [[ -e "$d" ]] && dirs+=("$d")
  done
  ((${#dirs[@]})) || return 0

  section "Old nvim data"
  info "an existing nvim config was replaced; its plugins/cache are still in:"
  for d in "${dirs[@]}"; do hint "${d/#$HOME/~}"; done
  info "answer N if it was already this config (e.g. re-linking the same machine)"
  if confirm "Move them to the backup too?"; then
    for d in "${dirs[@]}"; do backup "$d"; done
  else
    info "left in place"
  fi
}

install_oh_my_zsh() {
  section "Oh My Zsh"
  if [[ ! -d "$ZSH_DIR" ]]; then
    git clone --depth=1 --quiet https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR"
    ok "cloned Oh My Zsh"  # fresh-home.sh greps for "cloned "
  else
    ok "Oh My Zsh ($ZSH_DIR)"
  fi
  # Oh My Zsh's sample zshrc, comments and all, which a migrated ~/.zshrc.local
  # points to. Anything already at ~/.zshrc.example is left alone.
  local example="$HOME/.zshrc.example" template="$ZSH_DIR/templates/zshrc.zsh-template"
  if [[ -f "$template" && ! -e "$example" && ! -L "$example" ]]; then
    ln -s "$template" "$example"
    info "linked ~/.zshrc.example -> ${template/#$HOME/~}"  # fresh-home.sh greps for "linked "
  fi
}

install_tmux_plugins() {
  section "tmux plugins (TPM)"
  if [[ ! -d "$TPM_DIR" ]]; then
    git clone --quiet https://github.com/tmux-plugins/tpm "$TPM_DIR"
    ok "cloned TPM"  # fresh-home.sh greps for "cloned "
  fi
  # Private tmux server so we neither touch nor read a running session (whose
  # environment would also leak TMUX_PLUGIN_MANAGER_PATH in).
  local sock
  sock="$(mktemp -d)"
  env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH TMUX_TMPDIR="$sock" "$TPM_DIR/bin/install_plugins" | sed 's/^/  /'
  env -u TMUX TMUX_TMPDIR="$sock" tmux kill-server 2>/dev/null || true
  rm -rf "$sock"
  ok "plugins installed"

  # resurrect saves through ~/.tmux/resurrect when it's a folder, else in its
  # XDG folder; link the first to the second so both paths show the saves.
  # An existing ~/.tmux/resurrect (a folder, or a link anywhere) is left
  # alone: resurrect already saves through it. doctor.sh doesn't check this
  # convenience link.
  local link="$HOME/.tmux/resurrect" saves="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
  if [[ ! -e "$link" && ! -L "$link" ]]; then
    mkdir -p "$saves"
    ln -s "$saves" "$link"
    info "linked ~/.tmux/resurrect -> ${saves/#$HOME/~}"  # fresh-home.sh greps for "linked ~/.tmux/resurrect -> "
  fi
}

install_nvim_plugins() {
  section "nvim plugins (lazy.nvim)"
  local log="$HOME/.dotfiles-install.log"
  : >"$log"
  # The first installs what's missing at the latest commits. The second writes
  # this machine's lockfile in full: the first's misses the plugins NvChad's
  # spec imports, and an up-to-date machine doesn't write one at all.
  run_logged "$log" nvim --headless +qa
  run_logged "$log" nvim --headless "+Lazy! install" +qa
  ok "plugins installed (versions: ${NVIM_LOCK/#$HOME/~})"

  info "installing treesitter parsers: $(wanted_parsers | tr '\n' ' ')"
  run_logged "$log" nvim --headless \
    "+lua require('lazy').load({ plugins = { 'nvim-treesitter' } })" \
    "+lua require('nvim-treesitter').install(require('configs.treesitter').ensure_installed):wait(300000)" \
    +qa
  ok "parsers installed (details: ${log/#$HOME/~})"
}

# A first install starts the reminder's clock, so a new machine stays quiet.
start_update_clock() {
  [[ -e "$UPDATE_STAMP" ]] && return 0
  mkdir -p "$(dirname "$UPDATE_STAMP")"
  touch "$UPDATE_STAMP"
}

next_steps() {
  section "Done. Next steps"
  info "restart Ghostty, tmux (tmux kill-server), and open a new shell to pick everything up"
  info "check this machine anytime:   $REPO_DIR/doctor.sh"
  info "update this machine:          $REPO_DIR/update.sh"
  info "get changes to the repo:       cd $REPO_DIR && git pull && ./install.sh"
  info "nvim comes set up with NvChad. Press Space c h in nvim for a cheatsheet of the keyboard shortcuts."  # fresh-home.sh greps for "Press Space c h in nvim"
  info "Rectangle needs Accessibility permission, which you grant by hand: System Settings > Privacy & Security > Accessibility"
  local f files=""
  for f in "${LOCAL_FILES[@]}"; do files+="${files:+, }${f/#$HOME/~}"; done
  info "per-machine tweaks (not in git): $files"
  extras_cue
  printf '\n  %sLanguage support (Java, Python, Go) is NOT installed on purpose.%s\n' "$C_BOLD" "$C_OFF"
  hint "when you need one, follow $REPO_DIR/LANGUAGES.md"
  hint "doctor.sh shows which languages are set up and what's missing"
  [[ -d "$BACKUP_DIR" ]] && info "backups from this run: ${BACKUP_DIR/#$HOME/~}"
  return 0
}

check_prereqs
install_tools
install_oh_my_zsh # before the zshrc link, so a failed clone leaves the old shell config in place
link_configs
section "Commit hook"
enable_commit_hook "$REPO_DIR"
maybe_reset_nvim_data
install_tmux_plugins
install_nvim_plugins
start_update_clock
next_steps
