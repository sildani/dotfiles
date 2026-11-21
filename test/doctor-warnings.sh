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

SSH_AGENT_HINT='launchd provides an agent on demand'

# expect_ssh_agent <files it warns about, e.g. ".zprofile .zshrc.local"> <case>
expect_ssh_agent() {
  local out file
  out="$(doctor)"
  for file in .zprofile .zshrc.local; do
    if [[ " $1 " == *" $file "* ]]; then
      [[ "$out" =~ ssh-agent\ in\ ~/$file\ can\ leave\ one\ per\ shell\ \([1-9][0-9]*\ running\ now\) ]] ||
        failed "$2: no counted warning about ssh-agent in ~/$file:"$'\n'"$out"
    else
      [[ "$out" != *"ssh-agent in ~/$file"* ]] || failed "$2: warned about ssh-agent in ~/$file"
    fi
  done
  # One hint under each warning.
  local hints expected
  hints="$(grep -cF "$SSH_AGENT_HINT" <<<"$out" || true)"
  expected="$(wc -w <<<"$1" | tr -d ' ')"
  ((hints == expected)) || failed "$2: '$SSH_AGENT_HINT' $hints times, expected $expected"
}

# One real agent for doctor.sh to count. Its socket goes under its HOME, and
# $TMP's path is too long for a socket.
agent_home="$(mktemp -d /tmp/doctor-warnings-agent.XXXXXX)"
agent_env="$(HOME="$agent_home" ssh-agent -s)" || failed "ssh-agent didn't start"
eval "$agent_env" >/dev/null
trap 'ssh-agent -k >/dev/null 2>&1; rm -rf "$TMP" "$agent_home"' EXIT
# shellcheck disable=SC2016  # literal lines for the startup files
AGENT_LINE='eval "$(ssh-agent -s)" > /dev/null 2>&1'

expect_ssh_agent "" "neither startup file"

# shellcheck disable=SC2016  # literal lines for the startup files
printf '%s\n' '# eval "$(ssh-agent -s)"' 'export SSH_AUTH_SOCK=~/.ssh/ssh-agent.sock' |
  tee "$HOME/.zprofile" >"$HOME/.zshrc.local"
expect_ssh_agent "" "a comment and a socket path in both files"

echo "$AGENT_LINE" >>"$HOME/.zshrc.local"
expect_ssh_agent .zshrc.local "agent line in ~/.zshrc.local"

echo "$AGENT_LINE" >>"$HOME/.zprofile"
expect_ssh_agent ".zprofile .zshrc.local" "agent lines in both files"

rm "$HOME/.zshrc.local"
expect_ssh_agent .zprofile "agent line in ~/.zprofile"
rm "$HOME/.zprofile"

LOOKALIKE='Lookalike of shrink'
# Folders a case puts on PATH ahead of $TMP/bin, set with on_path.
LOOK_PATH=""
on_path() { LOOK_PATH="$(printf '%s:' "$@")"; }
# look_doctor: doctor.sh with LOOK_PATH, then its exit status on a last line.
# Only a fake Homebrew and system folders follow LOOK_PATH, so this Mac's own
# commands stay out. The fake brew gives $TMP/brew as its prefix and passes
# everything else to the real one.
real_brew="$(command -v brew || echo /opt/homebrew/bin/brew)"
mkdir -p "$TMP/brew/bin"
# shellcheck disable=SC2016  # $1, $# and $@ are the fake's own
printf '#!/bin/sh\n[ "$1" = --prefix ] && [ $# = 1 ] && { echo %s; exit; }\nexec %s "$@"\n' "$TMP/brew" "$real_brew" >"$TMP/brew/bin/brew"
chmod +x "$TMP/brew/bin/brew"
look_doctor() {
  local rc=0
  PATH="$LOOK_PATH$TMP/bin:$TMP/brew/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$TMP/repo/doctor.sh" 2>&1 || rc=$?
  echo "exit $rc"
}
# executable <path>...: empty scripts.
executable() {
  local f
  for f in "$@"; do
    mkdir -p "$(dirname "$f")"
    printf '#!/bin/sh\n' >"$f"
    chmod +x "$f"
  done
}

# expect_lookalikes <case> <warning line>...: the Lookalike warnings are those
# lines exactly, and they don't change doctor.sh's exit status or problem count.
take_baseline() { baseline="$(look_doctor | grep -E 'problem|^exit')"; }
take_baseline
expect_lookalikes() {
  local name="$1" out got want
  shift
  out="$(look_doctor)"
  got="$(grep -F "$LOOKALIKE" <<<"$out" | sed 's/^[^!]*! //' || true)"
  want="$(printf '%s\n' "$@" | sed '/^$/d')"
  [[ "$got" == "$want" ]] || failed "$name: Lookalike warnings were:"$'\n'"$got"$'\n'"expected:"$'\n'"$want"
  [[ "$(grep -E 'problem|^exit' <<<"$out")" == "$baseline" ]] ||
    failed "$name: changed doctor.sh's result:"$'\n'"$(grep -E 'problem|^exit' <<<"$out")"$'\n'"was:"$'\n'"$baseline"
}

expect_lookalikes "no Lookalikes"

executable "$TMP/look/bin/vidcompress"
on_path "$TMP/look/bin"
expect_lookalikes "vidcompress on PATH" \
  "$LOOKALIKE: command vidcompress in $TMP/look/bin"

# /usr/bin/compress, on every Mac, stays quiet in all of these.
executable "$TMP/brew/bin/squashfs" "$TMP/look/bin/MP4Small"
expect_lookalikes "MP4Small on PATH, squashfs in Homebrew's bin" \
  "$LOOKALIKE: command MP4Small in $TMP/look/bin" \
  "$LOOKALIKE: command vidcompress in $TMP/look/bin"
rm -r "$TMP/look" "$TMP/brew/bin/squashfs"

# The repo's shrink, linked where install.sh links it.
mkdir -p "$HOME/.local/bin"
ln -s "$TMP/repo/bin/shrink" "$HOME/.local/bin/shrink"
take_baseline # the link is one doctor.sh checks
executable "$TMP/brew/bin/shrink"
on_path "$HOME/.local/bin"
expect_lookalikes "the repo's shrink ahead of Homebrew's"

on_path "$TMP/brew/bin" "$HOME/.local/bin"
expect_lookalikes "Homebrew's shrink ahead of the repo's" \
  "$LOOKALIKE: another shrink in $TMP/brew/bin runs instead of the repo's"
rm "$TMP/brew/bin/shrink"

executable "$TMP/look/bin/shrink" "$TMP/look/bin/shrinkpdf"
on_path "$TMP/look/bin" "$HOME/.local/bin"
expect_lookalikes "another shrink ahead of the repo's, next to shrinkpdf" \
  "$LOOKALIKE: another shrink in $TMP/look/bin runs instead of the repo's" \
  "$LOOKALIKE: command shrinkpdf in $TMP/look/bin"
rm -r "$TMP/look"
on_path

# Definitions in the per-machine file and Oh My Zsh's custom folder; comments,
# calls and other names stay quiet.
# The repo's ~/.zshrc and an overdue Update reminder, which an interactive zsh
# would show and restart.
mkdir -p "$HOME/.oh-my-zsh/custom/plugins/vid" "$(dirname "$UPDATE_STAMP")"
ln -s "$TMP/repo/zsh/zshrc" "$HOME/.zshrc"
touch -t 202001010000 "$UPDATE_STAMP"
stamp_was="$(stat -f %m "$UPDATE_STAMP")"
take_baseline # Oh My Zsh's folder and ~/.zshrc are ones doctor.sh checks
cat >"$HOME/.zshrc.local" <<'ZSH'
# alias minifyjs='terser'
myshrink() {
  ffmpeg -i "$1" "small-$1"
}
myshrink a.mov
alias ll='ls -l'
ZSH
cat >"$HOME/.oh-my-zsh/custom/aliases.zsh" <<'ZSH'
  alias squashpdf='gs -sDEVICE=pdfwrite'
greet() { echo hi; }
ZSH
cat >"$HOME/.oh-my-zsh/custom/plugins/vid/vid.plugin.zsh" <<'ZSH'
function Compress_All {
  :
}
ZSH
expect_lookalikes "a function and aliases in startup files" \
  "$LOOKALIKE: function myshrink in ~/.zshrc.local:2" \
  "$LOOKALIKE: alias squashpdf in ~/.oh-my-zsh/custom/aliases.zsh:1" \
  "$LOOKALIKE: function Compress_All in ~/.oh-my-zsh/custom/plugins/vid/vid.plugin.zsh:1"
[[ "$(stat -f %m "$UPDATE_STAMP")" == "$stamp_was" ]] ||
  failed "doctor.sh restarted the Update reminder's count"

if ((failures)); then
  echo "doctor-warnings: $failures failed" >&2
  exit 1
fi
echo "doctor-warnings: ok"
