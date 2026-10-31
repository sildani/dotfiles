#!/bin/bash
# PROTOTYPE, delete me. Answers one question: what should the Ghostty window's
# corners look like? Opens real windows with command-line overrides, so it
# changes no config file.
#
#   ghostty/prototype-corners.sh          open A, B and C side by side
#   ghostty/prototype-corners.sh D        open one variant
#   ghostty/prototype-corners.sh close    close every prototype window
set -u

GHOSTTY_APP=/Applications/Ghostty.app
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
MARKER=prototype-corners

variant_name() {
  case "$1" in
    A) echo "Current: hidden title bar, rounded" ;;
    B) echo "No decoration, square, shadow" ;;
    C) echo "No decoration, square, flat" ;;
    D) echo "Borderless full screen" ;;
  esac
}

variant_args() {
  case "$1" in
    A) ;;
    B) echo "--window-decoration=none" ;;
    C) echo "--window-decoration=none --macos-window-shadow=false" ;;
    D) echo "--fullscreen=true --macos-non-native-fullscreen=true" ;;
  esac
}

open_variant() {
  # $1 variant, $2 window-position-x
  # shellcheck disable=SC2046 # variant_args is a flag list to split
  open -na "$GHOSTTY_APP" --args \
    "--title=$MARKER-$1" \
    "--command=$SELF shell $1" \
    --window-width=60 --window-height=24 \
    "--window-position-x=$2" --window-position-y=120 \
    --window-save-state=never \
    --confirm-close-surface=false \
    --quit-after-last-window-closed=true \
    $(variant_args "$1")
}

case "${1:-all}" in
  all)
    open_variant A 40
    open_variant B 620
    open_variant C 1200
    ;;
  A | B | C | D) open_variant "$1" 40 ;;
  shell)
    # Runs inside the window: show the variant, then hand over to a real shell.
    echo "Variant $2: $(variant_name "$2")"
    echo "Flags: $(variant_args "$2")"
    echo "Try: Option+drag an edge to move, drag an edge to resize"
    exec /bin/zsh -l
    ;;
  close) pkill -f -- "--title=$MARKER-" ;;
  *)
    echo "usage: $0 [A|B|C|D|close]" >&2
    exit 2
    ;;
esac
