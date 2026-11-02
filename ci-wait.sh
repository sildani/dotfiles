#!/usr/bin/env bash
# Usage: ./ci-wait.sh <full-sha>
# Waits for the CI run on a commit pushed to a PR (or to main) and exits with
# its result: 0 when it succeeded, 1 when it didn't or no run appeared, 2 for a
# bad argument. Run it in the background; it prints one line, with the run ID,
# its conclusion, the SHA and each job's result.
# - The SHA must be all 40 hex characters: gh run list --commit matches a short
#   one to nothing.
# - It polls every CI_WAIT_POLL seconds (15), CI_WAIT_TRIES times (16, about 4
#   minutes), until a run appears.
# - With several runs for the SHA, it watches the newest.
# - gh run watch repeats the job list every 3 seconds, so its output goes to a
#   log, kept and named only when the run fails.
set -euo pipefail

sha="${1:-}"
case "$sha" in
  -h | --help)
    sed -nE '2,/^set /s/^# ?//p' "$0"
    exit 0 ;;
esac
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "ci-wait: '$sha' isn't a full SHA (40 hex characters); try: git rev-parse HEAD" >&2
  exit 2
fi
cd "$(dirname "${BASH_SOURCE[0]}")"
tries="${CI_WAIT_TRIES:-16}" poll="${CI_WAIT_POLL:-15}"

run=""
for ((try = 1; try <= tries; try++)); do
  ((try == 1)) || sleep "$poll"
  # Newest first; .[] keeps "no run yet" empty, where .[0] would print null.
  run="$(gh run list --commit "$sha" --json databaseId --jq '.[].databaseId')"
  run="${run%%$'\n'*}"
  [[ -n "$run" ]] && break
done
if [[ -z "$run" ]]; then
  echo "ci-wait: no CI run for $sha after $(((tries - 1) * poll))s; CI runs on PRs and main: is a PR open for it?" >&2
  exit 1
fi

log="$(mktemp -t ci-wait)"
gh run watch "$run" --exit-status >"$log" 2>&1 || true
summary="$(gh run view "$run" --json databaseId,conclusion,headSha,jobs \
  --jq '"ci-wait: run \(.databaseId) \(.conclusion) \(.headSha) " + ([.jobs[] | "\(.name)=\(.conclusion)"] | join(" "))')" ||
  summary="ci-wait: run $run: gh run view failed"
echo "$summary"
if [[ "$summary" == "ci-wait: run $run success "* ]]; then
  rm -f "$log"
  exit 0
fi
echo "ci-wait: failed steps: gh run view $run --log-failed (watch log: $log)" >&2
exit 1
