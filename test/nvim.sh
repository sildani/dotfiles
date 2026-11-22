#!/usr/bin/env bash
# Headless nvim checks against the current HOME's installed config and
# plugins, in seconds: render-markdown loads for a markdown file, and Space m r
# is mapped in markdown buffers only. Installed means ~/.config/nvim is a
# symlink to a dotfiles checkout's nvim/ (install.sh's link; in a worktree that
# is the main checkout's, not this one's). Without it, prints a skip line on
# stderr and exits 0, as in CI's lint job; test/fresh-home.sh fails on it.
set -euo pipefail
# shellcheck source=lib/test-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-guard.sh"

link="$HOME/.config/nvim"
config=""
[[ -L "$link" ]] && config="$(cd -P "$link" 2>/dev/null && pwd)" || true
if [[ -z "$config" || "${config##*/}" != nvim || ! -f "$config/../install.sh" || ! -f "$config/../lib/common.sh" ]]; then
  echo "test/nvim.sh: skipped, nvim config not installed in $HOME" >&2  # fresh-home.sh greps for "test/nvim.sh: skipped"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $1" >&2
  [[ -s "$TMP/nvim.log" ]] && { echo "--- nvim's output" >&2; tail -20 "$TMP/nvim.log" >&2; echo >&2; }
  exit 1
}

echo "nvim renders markdown, with Space m r in markdown buffers only"
printf '# Notes\n\n| a | b |\n| - | - |\n| 1 | 2 |\n' >"$TMP/notes.md"
echo 'return {}' >"$TMP/notes.lua"
out="$TMP/md-check.out"
nvim --headless "$TMP/notes.md" \
  "+lua local function buffer_mapped() return vim.fn.maparg('<leader>mr', 'n', false, true).buffer == 1 end
    local function any_mapping() return vim.fn.maparg('<leader>mr', 'n') ~= '' end
    local out = { 'loaded=' .. tostring(package.loaded['render-markdown'] ~= nil), 'md_map=' .. tostring(buffer_mapped()) }
    vim.cmd.edit('$TMP/notes.lua')
    out[#out + 1] = 'lua_map=' .. tostring(any_mapping())
    vim.fn.writefile(out, '$out')" +qa >"$TMP/nvim.log" 2>&1 || fail "nvim exited non-zero opening a markdown file"
# A Lua error still exits 0, but then the file isn't written and this fails.
result=""
[[ -f "$out" ]] && result="$(tr '\n' ' ' <"$out")"
[[ "$result" == 'loaded=true md_map=true lua_map=false ' ]] ||
  fail "nvim should load render-markdown and map Space m r for markdown buffers only, got: ${result:-nothing (a Lua error?)}"

echo "test/nvim.sh: all passed"
