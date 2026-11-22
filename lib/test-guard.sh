# shellcheck shell=bash
# Source it from every test/*.sh, after its set -e. A command that stops a test
# there prints nothing of its own, so the output can pass for a good run: this
# names where it stopped. -E carries the ERR trap into functions. Failures inside
# $(...) stay quiet because the test may expect them, and one that matters stops
# the line holding the $(...). A bare ( ... ) that fails stays silent.
set -E

# Scripts must run on stock macOS bash 3.2, and a test's `env bash` shebang
# takes the first bash on PATH, which on the CI runner may be a newer one. So in
# CI (GitHub sets CI) a test refuses any bash but /bin/bash.
if [[ -n "${CI:-}" && "$BASH" != /bin/bash ]]; then
  echo "${0##*/}: runs on $BASH, not stock /bin/bash; CI puts /bin first on PATH" >&2
  exit 1
fi

# test_stopped <command> <line>: inside a function, stock bash's $LINENO is the
# function's first line, so name the function and its caller instead. Inside an
# `if` or a loop it's that block's last line.
test_stopped() {
  ((BASH_SUBSHELL == 0)) || return 0
  if [[ "${FUNCNAME[1]}" == main ]]; then
    echo "${0##*/}: died at line $2: $1" >&2
  else
    echo "${0##*/}: died in ${FUNCNAME[1]}, called from line ${BASH_LINENO[1]}: $1" >&2
  fi
}
trap 'test_stopped "$BASH_COMMAND" "$LINENO"' ERR
