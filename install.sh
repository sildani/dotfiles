#!/usr/bin/env bash
# Sets up tmux, nvim and Ghostty from this repo. Safe to re-run; re-running
# after `git pull` is also how you update. Never touches git/gh config or auth,
# and never installs language support (see LANGUAGES.md).
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
  info "moved ${1/#$HOME/~} -> ${dest/#$HOME/~}"
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

# Installs only what's missing. Existing installs are left alone whatever
# installed them; if they're too old we warn instead of replacing them.
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
      warn "$cmd $version is older than $min ($(tool_source "$cmd")); leaving it alone"
      if [[ "$(tool_source "$cmd")" == brew ]]; then
        hint "upgrade: brew upgrade $formula"
      else
        hint "upgrade it the way you installed it, or remove it and re-run to get brew's $formula"
      fi
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
}

link_configs() {
  section "Config links"
  local entry src dest
  for entry in "${LINKS[@]}"; do
    src="$REPO_DIR/${entry%%:*}"
    dest="${entry#*:}"
    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
      ok "${dest/#$HOME/~} already links to the repo"
      continue
    fi
    if [[ -e "$dest" || -L "$dest" ]]; then
      backup "$dest"
      [[ "$dest" == "$HOME/.config/nvim" ]] && nvim_config_replaced=true
    fi
    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
    ok "${dest/#$HOME/~} -> ${src/#$HOME/~}"
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

install_tmux_plugins() {
  section "tmux plugins (TPM)"
  if [[ ! -d "$TPM_DIR" ]]; then
    git clone --quiet https://github.com/tmux-plugins/tpm "$TPM_DIR"
    ok "cloned TPM"
  fi
  # Private tmux server so we neither touch nor read a running session (whose
  # environment would also leak TMUX_PLUGIN_MANAGER_PATH in).
  local sock
  sock="$(mktemp -d)"
  env -u TMUX -u TMUX_PLUGIN_MANAGER_PATH TMUX_TMPDIR="$sock" "$TPM_DIR/bin/install_plugins" | sed 's/^/  /'
  env -u TMUX TMUX_TMPDIR="$sock" tmux kill-server 2>/dev/null || true
  rm -rf "$sock"
  ok "plugins installed"
}

install_nvim_plugins() {
  section "nvim plugins (lazy.nvim, pinned by lazy-lock.json)"
  local log="$HOME/.dotfiles-install.log"
  : >"$log"
  run_logged "$log" nvim --headless "+Lazy! restore" +qa
  ok "plugins restored to lazy-lock.json"

  info "installing treesitter parsers: $(wanted_parsers | tr '\n' ' ')"
  run_logged "$log" nvim --headless \
    "+lua require('lazy').load({ plugins = { 'nvim-treesitter' } })" \
    "+lua require('nvim-treesitter').install(require('configs.treesitter').ensure_installed):wait(300000)" \
    +qa
  ok "parsers installed (details: ${log/#$HOME/~})"
}

next_steps() {
  section "Done. Next steps"
  info "restart Ghostty and tmux (tmux kill-server) to pick everything up"
  info "check this machine anytime:   $REPO_DIR/doctor.sh"
  info "update later:                 cd $REPO_DIR && git pull && ./install.sh"
  info "per-machine tweaks (not in git): ~/.tmux.local.conf, ~/.config/ghostty/local, nvim/lua/local.lua"
  printf '\n  %sLanguage support (Java, Python, Go) is NOT installed on purpose.%s\n' "$C_BOLD" "$C_OFF"
  hint "when you need one, follow $REPO_DIR/LANGUAGES.md"
  hint "doctor.sh shows which languages are set up and what's missing"
  [[ -d "$BACKUP_DIR" ]] && info "backups from this run: ${BACKUP_DIR/#$HOME/~}"
  return 0
}

check_prereqs
install_tools
link_configs
maybe_reset_nvim_data
install_tmux_plugins
install_nvim_plugins
next_steps
