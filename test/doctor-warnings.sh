#!/usr/bin/env bash
# Fast checks of doctor.sh's warnings: runs the real doctor.sh in an empty temp
# HOME with a fake defaults on PATH, which answers from plists written here, so
# a case can't touch or depend on this Mac's settings. doctor.sh's own result
# isn't checked: the empty HOME fails most of it, and warnings never do.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" PREFS="$TMP/prefs" GIT_CONFIG_NOSYSTEM=1
unset TMUX TMUX_PANE TMUX_PLUGIN_MANAGER_PATH XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME DOTFILES SSH_AGENT_PID SSH_AUTH_SOCK
mkdir -p "$HOME" "$PREFS" "$TMP/bin"

# Answers `defaults export <domain> -` from $PREFS/<domain>.plist.
cat >"$TMP/bin/defaults" <<'SHIM'
#!/bin/sh
[ "$1" = export ] || exit 1
cat "$PREFS/$2.plist"
SHIM
chmod +x "$TMP/bin/defaults"

failures=0
failed() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

plist() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>%s</dict></plist>\n' "$1"; }

# input_sources <kind>...: com.apple.HIToolbox with those sources enabled.
input_sources() {
  local kind entries=""
  for kind in "$@"; do
    entries+="<dict><key>InputSourceKind</key><string>$kind</string></dict>"
  done
  plist "<key>AppleEnabledInputSources</key><array>$entries</array>" >"$PREFS/com.apple.HIToolbox.plist"
}

# hotkey_60 <true|false> <a> <b> <c>: com.apple.symbolichotkeys with key 60 set.
hotkey_60() {
  plist "<key>AppleSymbolicHotKeys</key><dict><key>60</key><dict><key>enabled</key><$1/><key>value</key><dict><key>parameters</key><array><integer>$2</integer><integer>$3</integer><integer>$4</integer></array><key>type</key><string>standard</string></dict></dict></dict>" \
    >"$PREFS/com.apple.symbolichotkeys.plist"
}

# As a Mac that never changed the shortcut: other keys, but no 60.
no_hotkey_60() {
  plist '<key>AppleSymbolicHotKeys</key><dict><key>15</key><dict><key>enabled</key><false/></dict></dict>' \
    >"$PREFS/com.apple.symbolichotkeys.plist"
}

doctor() { PATH="$TMP/bin:$PATH" "$REPO_DIR/doctor.sh" 2>&1 || true; }

CTRL_SPACE='macOS takes Ctrl-Space'

# expect_ctrl_space <warns|quiet> <case>
expect_ctrl_space() {
  local out
  out="$(doctor)"
  if [[ "$out" == *"$CTRL_SPACE"* ]]; then
    [[ "$1" == warns ]] || failed "$2: warned about Ctrl-Space"
  else
    [[ "$1" == quiet ]] || failed "$2: no Ctrl-Space warning"
  fi
}

LAYOUT='Keyboard Layout' METHOD='Keyboard Input Method' NON_KEYBOARD='Non Keyboard Input Method'

input_sources "$LAYOUT" "$METHOD"
hotkey_60 true 32 49 262144
expect_ctrl_space warns "two input sources, key 60 enabled as Ctrl-Space"

no_hotkey_60
expect_ctrl_space warns "two input sources, key 60 absent"

input_sources "$LAYOUT" "$NON_KEYBOARD" "$NON_KEYBOARD" "$NON_KEYBOARD"
hotkey_60 true 32 49 262144
expect_ctrl_space quiet "one keyboard layout plus emoji entries, key 60 Ctrl-Space"

input_sources "$LAYOUT" "$LAYOUT"
hotkey_60 true 32 49 393216
expect_ctrl_space quiet "two input sources, key 60 moved to another shortcut"

hotkey_60 false 32 49 262144
expect_ctrl_space quiet "two input sources, key 60 disabled"

if ((failures)); then
  echo "doctor-warnings: $failures failed" >&2
  exit 1
fi
echo "doctor-warnings: ok"
