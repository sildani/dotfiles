#!/usr/bin/env bash
# Sourced by every test/*.sh, after its set -e. A command that stops a test there
# prints nothing of its own, so the output can pass for a good run: this names
# the line. -E carries the ERR trap into functions; failures inside $(...) stay
# quiet because the test may expect them, and one that matters stops the line
# holding the $(...).
set -E
trap 'stopped_by="$BASH_COMMAND"; ((BASH_SUBSHELL)) || echo "${0##*/}: stopped at line $LINENO: $stopped_by" >&2' ERR
