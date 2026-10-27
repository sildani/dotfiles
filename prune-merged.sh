#!/usr/bin/env bash
# Delete every branch already merged into main, on origin and locally. Run on
# the laptop after merging a PR. PRs here merge with a merge commit, so
# --merged finds every merged branch.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
git switch -q main
git pull -q --ff-only
git fetch -q --prune

remote=()
while IFS= read -r b; do
  case "$b" in main | HEAD) ;; *) remote+=("$b") ;; esac
done < <(git for-each-ref --merged origin/main --format='%(refname:lstrip=3)' refs/remotes/origin)

locals=()
while IFS= read -r b; do
  [[ "$b" == main ]] || locals+=("$b")
done < <(git for-each-ref --merged main --format='%(refname:short)' refs/heads)

if ((${#remote[@]})); then
  git push -q origin --delete "${remote[@]}"
fi
if ((${#locals[@]})); then
  git branch -q -d "${locals[@]}"
fi
echo "prune-merged: origin: ${remote[*]:-nothing to delete}"
echo "prune-merged: local: ${locals[*]:-nothing to delete}"
