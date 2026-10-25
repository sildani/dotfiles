# Shared by install.sh and doctor.sh. Source it; don't run it.
# shellcheck shell=bash
# shellcheck disable=SC2034  # variables are used by the scripts that source this

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MIN_TMUX="3.5"          # extended-keys-format
MIN_NVIM="0.12"         # nvim-treesitter main branch
MIN_TREE_SITTER="0.26.1" # nvim-treesitter main branch

NVIM_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
NVIM_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/nvim"
NVIM_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/nvim"
MASON_PKGS="$NVIM_DATA/mason/packages"
TS_PARSERS="$NVIM_DATA/site/parser"
TPM_DIR="$HOME/.tmux/plugins/tpm"
ZSH_DIR="$HOME/.oh-my-zsh"

# Ghostty on macOS also reads this directory, and it wins over ~/.config/ghostty.
GHOSTTY_LIBRARY_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
GHOSTTY_LIBRARY_FILES=("$GHOSTTY_LIBRARY_DIR/config" "$GHOSTTY_LIBRARY_DIR/config.ghostty")

# repo path -> link location
LINKS=(
  "zsh/zshrc:$HOME/.zshrc"
  "tmux/tmux.conf:$HOME/.tmux.conf"
  "nvim:$HOME/.config/nvim"
  "ghostty/config:$HOME/.config/ghostty/config"
)

# Per-machine overrides the shared configs load if present. Not in git.
LOCAL_FILES=(
  "$HOME/.zshrc.local"
  "$HOME/.tmux.local.conf"
  "$HOME/.config/ghostty/local"
  "$REPO_DIR/nvim/lua/local.lua"
)

# <tool>/extras/ snippets are turned on from this per-machine file (one of
# LOCAL_FILES). doctor.sh reports the ones in use; lint requires an entry
# for every extras folder.
EXTRAS_HOSTS=(
  "tmux:$HOME/.tmux.local.conf"
  "zsh:$HOME/.zshrc.local"
)

# brew formula : command : minimum version (empty = any)
FORMULAE=(
  "git:git:"
  "gh:gh:"
  "ripgrep:rg:"
  "tree-sitter-cli:tree-sitter:$MIN_TREE_SITTER"
  "tmux:tmux:$MIN_TMUX"
  "neovim:nvim:$MIN_NVIM"
)

if [[ -t 1 ]]; then
  C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_BLUE=$'\e[34m' C_DIM=$'\e[2m' C_BOLD=$'\e[1m' C_OFF=$'\e[0m'
else
  C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_DIM="" C_BOLD="" C_OFF=""
fi

section() { printf '\n%s== %s ==%s\n' "$C_BOLD" "$1" "$C_OFF"; }
ok()      { printf '  %s✓%s %s\n' "$C_GREEN" "$C_OFF" "$1"; }
info()    { printf '  %s•%s %s\n' "$C_BLUE" "$C_OFF" "$1"; }
warn()    { printf '  %s!%s %s\n' "$C_YELLOW" "$C_OFF" "$1"; }
fail()    { printf '  %s✗%s %s\n' "$C_RED" "$C_OFF" "$1"; }
hint()    { printf '    %s→ %s%s\n' "$C_DIM" "$1" "$C_OFF"; }

# One line pointing at the opt-in extras (<tool>/extras/), without listing them.
extras_cue() { info "optional extras you can turn on per machine: ${REPO_DIR/#$HOME/~}/README.md#optional-extras"; }  # fresh-home.sh greps for "optional extras"

# version_ge 3.5a 3.5 -> true. Compares the numeric dot-separated parts only.
version_ge() {
  local IFS=.
  local -a a b
  read -r -a a <<<"${1//[!0-9.]/}"
  read -r -a b <<<"${2//[!0-9.]/}"
  local i
  for ((i = 0; i < ${#b[@]}; i++)); do
    local x=$((10#${a[i]:-0})) y=$((10#${b[i]:-0}))
    ((x > y)) && return 0
    ((x < y)) && return 1
  done
  return 0
}

# Prints the first x.y[.z] found in the command's version output.
tool_version() {
  local out
  case "$1" in
    tmux) out="$(tmux -V 2>/dev/null)" ;;
    nvim) out="$(nvim --version 2>/dev/null | head -1)" ;;
    *) out="$("$1" --version 2>/dev/null | head -1)" ;;
  esac
  grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?[a-z]?' <<<"$out" | head -1
}

# "brew" if the command lives under the Homebrew prefix, otherwise its path.
tool_source() {
  local path
  path="$(command -v "$1")" || return 1
  if command -v brew >/dev/null && [[ "$path" == "$(brew --prefix)"/* ]]; then
    echo "brew"
  else
    echo "$path"
  fi
}

ghostty_app() {
  local app
  for app in /Applications/Ghostty.app "$HOME/Applications/Ghostty.app"; do
    [[ -d "$app" ]] && { echo "$app"; return 0; }
  done
  return 1
}

hurmit_font_installed() {
  compgen -G "$HOME/Library/Fonts/HurmitNerdFont*" >/dev/null ||
    compgen -G "/Library/Fonts/HurmitNerdFont*" >/dev/null
}

# Make brew usable in a fresh shell where it's installed but not on PATH yet.
load_brew() {
  command -v brew >/dev/null && return 0
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$b" ]] && { eval "$("$b" shellenv)"; return 0; }
  done
  return 1
}

# Uncommented "name", entries from the nvim treesitter parser list.
wanted_parsers() {
  sed -nE 's/^[[:space:]]*"([a-z_]+)",.*/\1/p' "$REPO_DIR/nvim/lua/configs/treesitter.lua"
}
