#!/usr/bin/env bash
# Usage: ./ci-wait.sh <full-sha>
# Waits for the CI run on a pushed commit and exits with its result: 0 when it
# succeeded, 1 when it didn't or no run appeared, 2 for a bad argument. Run it
# in the background; it prints one line, with the run ID, its conclusion, the
# SHA and each job's result.
# - The SHA must be all 40 hex characters: gh run list --commit matches a short
#   one to nothing.
# - It polls every CI_WAIT_POLL seconds (15), CI_WAIT_TRIES times (16, about 4
#   minutes), until a run appears.
# - With several runs for the SHA, it watches the newest.
# - gh run watch repeats the job list every 3 seconds, so its output goes to a
#   log, kept and named only when the run fails.
set -euo pipefail

sha="${1:-}"
if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
  echo "ci-wait: '$sha' isn't a full SHA (40 hex characters); try: git rev-parse HEAD" >&2
  exit 2
fi
cd "$(dirname "${BASH_SOURCE[0]}")"

run=""
for ((try = 1; try <= ${CI_WAIT_TRIES:-16}; try++)); do
  ((try == 1)) || sleep "${CI_WAIT_POLL:-15}"
  # Newest first; .[] keeps "no run yet" empty, where .[0] would print null.
  run="$(gh run list --commit "$sha" --json databaseId --jq '.[].databaseId')"
  run="${run%%$'\n'*}"
  [[ -n "$run" ]] && break
done
if [[ -z "$run" ]]; then
  echo "ci-wait: no CI run for $sha after $(( (${CI_WAIT_TRIES:-16} - 1) * ${CI_WAIT_POLL:-15} ))s; is it pushed?" >&2
  exit 1
fi

log="$(mktemp -t ci-wait)"
gh run watch "$run" --exit-status >"$log" 2>&1 || true
summary="$(gh run view "$run" --json databaseId,conclusion,headSha,jobs \
  --jq '"ci-wait: run \(.databaseId) \(.conclusion) \(.headSha) " + ([.jobs[] | "\(.name)=\(.conclusion)"] | join(" "))')"
echo "$summary"
read -r _ _ _ conclusion _ <<<"$summary"
if [[ "$conclusion" == success ]]; then
  rm -f "$log"
  exit 0
fi
echo "ci-wait: failed steps: gh run view $run --log-failed (watch log: $log)" >&2
exit 1
