#!/usr/bin/env bash
# Fast checks of ci-wait.sh, on stock bash, against a fake gh on PATH that
# records its calls and runs the script's --jq expressions through jq: --help,
# a short SHA refused, no run yet then success, failure, gh run view failing,
# and no run at all.
set -euo pipefail
# shellcheck source=lib/test-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-guard.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
failed() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

SHA=0123456789abcdef0123456789abcdef01234567
# EMPTY_LISTS: how many `gh run list` calls find no run yet. CONCLUSION: the
# run's. FAIL_VIEW: set to make `gh run view` fail.
export CALLS="$TMP/calls" LISTS="$TMP/lists" SHA EMPTY_LISTS CONCLUSION FAIL_VIEW=""
mkdir "$TMP/bin"
# shellcheck disable=SC2016  # for the fake gh
cat >"$TMP/bin/gh" <<'FAKE'
#!/bin/sh
echo "gh $*" >>"$CALLS"
expr="" prev=""
for a in "$@"; do
  [ "$prev" = --jq ] && expr="$a"
  prev="$a"
done
case "$1 $2" in
  "run list")
    n="$(cat "$LISTS" 2>/dev/null || echo 0)"
    echo $((n + 1)) >"$LISTS"
    json='[{"databaseId":222},{"databaseId":111}]'
    [ "$n" -lt "$EMPTY_LISTS" ] && json='[]' ;;
  "run watch")
    echo "watch noise: lint, fresh-home"
    [ "$CONCLUSION" = success ]
    exit ;;
  "run view")
    [ -z "$FAIL_VIEW" ] || exit 1
    json="{\"databaseId\":$3,\"conclusion\":\"$CONCLUSION\",\"headSha\":\"$SHA\",\"jobs\":[{\"name\":\"lint\",\"conclusion\":\"success\"},{\"name\":\"fresh-home\",\"conclusion\":\"$CONCLUSION\"}]}" ;;
  *)
    echo "fake gh: unexpected call: $*" >&2
    exit 64 ;;
esac
printf '%s\n' "$json" | jq -r "$expr"
FAKE
chmod +x "$TMP/bin/gh"

# ci_wait <args>: runs ci-wait.sh with the fake gh, no wait between polls;
# sets out, err and rc.
ci_wait() {
  rm -f "$CALLS" "$LISTS"
  rc=0
  out="$(PATH="$TMP/bin:$PATH" CI_WAIT_POLL=0 CI_WAIT_TRIES=3 /bin/bash "$REPO_DIR/ci-wait.sh" "$@" 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"
}
calls() { grep -c "^gh $1" "$CALLS" 2>/dev/null || true; }

echo "--help"
ci_wait --help
((rc == 0)) || failed "--help should exit 0, exited $rc"
[[ "$out" == "Usage: ./ci-wait.sh <full-sha>"* && "$out" == *"it watches the newest"* ]] ||
  failed "--help should print the usage and say which run it watches: $out"
[[ ! -e "$CALLS" ]] || failed "--help called gh: $(cat "$CALLS")"

echo "a short SHA is refused"
EMPTY_LISTS=0 CONCLUSION=success
for bad in 0123456 "${SHA}0" "${SHA%?}G" ""; do
  ci_wait "$bad"
  ((rc == 2)) || failed "'$bad' should exit 2, exited $rc"
  [[ "$err" == *"40 hex"* ]] || failed "'$bad' should say a full SHA is 40 hex characters: $err"
  [[ ! -e "$CALLS" ]] || failed "'$bad' called gh: $(cat "$CALLS")"
done

echo "no run yet, then success"
EMPTY_LISTS=2 CONCLUSION=success
ci_wait "$SHA"
((rc == 0)) || failed "success should exit 0, exited $rc: $out $err"
[[ "$out" == "ci-wait: run 222 success $SHA lint=success fresh-home=success" ]] ||
  failed "success should print one summary line, printed: $out"
[[ "$(calls 'run list')" == 3 ]] || failed "should poll until a run appears: $(cat "$CALLS")"
grep -q "^gh run list --commit $SHA " "$CALLS" || failed "should list the runs for the SHA: $(cat "$CALLS")"
grep -q '^gh run watch 222 ' "$CALLS" || failed "should watch the newest run, 222: $(cat "$CALLS")"
[[ "$out$err" != *"watch noise"* ]] || failed "gh run watch's output reached the terminal: $out $err"

echo "failure"
EMPTY_LISTS=0 CONCLUSION=failure
ci_wait "$SHA"
((rc == 1)) || failed "failure should exit 1, exited $rc"
[[ "$out" == "ci-wait: run 222 failure $SHA lint=success fresh-home=failure" ]] ||
  failed "failure should print one summary line, printed: $out"
[[ "$err" == *"gh run view 222 --log-failed"* ]] || failed "failure should name the failed-steps command: $err"
[[ "$out$err" != *"watch noise"* ]] || failed "gh run watch's output reached the terminal: $out $err"

echo "gh run view failing"
EMPTY_LISTS=0 CONCLUSION=success FAIL_VIEW=1
ci_wait "$SHA"
FAIL_VIEW=""
((rc == 1)) || failed "a failed gh run view should exit 1, exited $rc"
[[ "$out" == "ci-wait: run 222: gh run view failed" ]] || failed "a failed gh run view should still print one line: $out"

echo "no run at all"
EMPTY_LISTS=99 CONCLUSION=success
ci_wait "$SHA"
((rc == 1)) || failed "no run should exit 1, exited $rc"
[[ "$err" == *"no CI run for $SHA"*"is a PR open"* ]] || failed "no run should say so and ask about a PR: $err"
[[ "$(calls 'run list')" == 3 ]] || failed "should give up after CI_WAIT_TRIES polls: $(cat "$CALLS")"
[[ "$(calls 'run watch')" == 0 ]] || failed "nothing to watch, but watched: $(cat "$CALLS")"

if ((failures)); then
  echo "ci-wait: $failures failed" >&2
  exit 1
fi
echo "ci-wait: ok"
