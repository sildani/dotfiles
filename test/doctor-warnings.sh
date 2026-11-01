#!/usr/bin/env bash
# Fast checks of doctor.sh's warnings: runs a copy's real doctor.sh in an empty
# temp HOME with a fake defaults on PATH, which answers from plists written
# here, so a case can't touch or depend on this Mac's settings, and with a local
# bare repo as the copy's origin. doctor.sh's own result isn't checked, except
# that a warning doesn't fail it: the empty HOME fails the rest.
set -euo pipefail
# shellcheck source=lib/test-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-guard.sh"

REAL_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" PREFS="$TMP/prefs" GIT_CONFIG_NOSYSTEM=1
unset TMUX TMUX_PANE TMUX_PLUGIN_MANAGER_PATH XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME DOTFILES SSH_AGENT_PID SSH_AUTH_SOCK
mkdir -p "$HOME" "$PREFS" "$TMP/bin"
# shellcheck source=lib/common.sh
source "$REAL_REPO_DIR/lib/common.sh"
copy_worktree "$REAL_REPO_DIR" "$TMP/repo"
git -C "$TMP/repo" branch -q -M main

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

doctor() { PATH="$TMP/bin:$PATH" "$TMP/repo/doctor.sh" 2>&1 || true; }

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

BEHIND='behind origin' NO_ORIGIN="couldn't reach origin"

# expect_origin <text it prints> <text it doesn't> <case>
expect_origin() {
  local out
  out="$(doctor)"
  [[ "$out" == *"$1"* ]] || failed "$3: no '$1':"$'\n'"$out"
  [[ "$out" != *"$2"* ]] || failed "$3: printed '$2':"$'\n'"$out"
}

git init -q --bare -b main "$TMP/origin.git"
git -C "$TMP/repo" remote add origin "$TMP/origin.git"
git -C "$TMP/repo" push -q origin main
expect_origin 'up to date with origin' "$BEHIND" "HEAD at origin's main"

git clone -q "$TMP/origin.git" "$TMP/other"
git -C "$TMP/other" -c user.name=t -c user.email=t@localhost commit -q --allow-empty -m ahead
git -C "$TMP/other" push -q origin HEAD:main
expect_origin "$BEHIND" "$NO_ORIGIN" "origin's main has a commit HEAD lacks"

git -C "$TMP/repo" fetch -q origin main
expect_origin "$BEHIND" "$NO_ORIGIN" "origin's main fetched but not merged"

git -C "$TMP/repo" merge -q --ff-only FETCH_HEAD
git -C "$TMP/repo" -c user.name=t -c user.email=t@localhost commit -q --allow-empty --no-verify -m local
expect_origin 'up to date with origin' "$BEHIND" "HEAD ahead of origin's main"

git -C "$TMP/repo" remote set-url origin "$TMP/no-such-repo"
expect_origin "$NO_ORIGIN" "$BEHIND" "origin unreachable"

# Fails the whole test, not just a case, if the time limit doesn't hold.
real_git="$(command -v git)"
printf '#!/bin/sh\ncase "$*" in *ls-remote*) exec sleep 60 ;; esac\nexec %s "$@"\n' "$real_git" >"$TMP/bin/git"
chmod +x "$TMP/bin/git"
started=$SECONDS
expect_origin "$NO_ORIGIN" "$BEHIND" "origin hangs"
((SECONDS - started < 20)) || failed "doctor.sh took $((SECONDS - started))s with a hanging origin"
rm "$TMP/bin/git"

if ((failures)); then
  echo "doctor-warnings: $failures failed" >&2
  exit 1
fi
echo "doctor-warnings: ok"
