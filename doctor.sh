#!/usr/bin/env bash
# Read-only health check: what's installed, what's linked, and which languages
# are set up. Changes nothing. Exits non-zero if something is broken (✗);
# warnings (!) and language status never fail it.
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
      hint "upgrade it the way it was installed (brew: brew upgrade $formula)"
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
      hint "run ./install.sh (it backs up the old target first)"
    elif [[ -e "$dest" ]]; then
      broken "${dest/#$HOME/~} is a regular file/dir, not a link to the repo"
      hint "run ./install.sh (it backs up the old one first)"
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
    local name missing=()
    while read -r name; do
      [[ -d "$HOME/.tmux/plugins/$name" ]] || missing+=("$name")
    done < <(sed -nE "s/^set -g @plugin '[^/]+\/([^'#]+).*/\1/p" "$REPO_DIR/tmux/tmux.conf")
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

  local missing=()
  while read -r name; do
    [[ -d "$NVIM_DATA/lazy/$name" ]] || missing+=("$name")
  done < <(sed -nE 's/^  "([^"]+)": \{.*/\1/p' "$REPO_DIR/nvim/lazy-lock.json")
  if ((${#missing[@]})); then
    broken "nvim plugins missing: ${missing[*]}"
    hint "run ./install.sh (or :Lazy restore in nvim)"
  else
    ok "all nvim plugins in lazy-lock.json"
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

check_tools
check_shell
check_links
check_plugins
check_languages

echo
if ((failures)); then
  printf '%s%d problem(s) found.%s Fix hints are under each ✗ line.\n' "$C_RED" "$failures" "$C_OFF"
  exit 1
fi
printf '%sAll good.%s\n' "$C_GREEN" "$C_OFF"
