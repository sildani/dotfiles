# shellcheck shell=bash
# The tests the commit hook runs (test/<name>.sh), after test/lint.sh.
# Sourced by hooks/pre-commit, and by test/fresh-home.sh to check the hook.
# shellcheck disable=SC2034  # used by the scripts that source this
HOOK_TESTS=(doctor-warnings updates ci-wait shrink tidy-names)
