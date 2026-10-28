#!/usr/bin/env bash
# Checks that test/lint.sh's marker and extras checks still catch what they
# exist for: in a copy of the working tree, it removes each
# `# fresh-home.sh greps for "<text>"` marker, rewords one, adds an unmarked
# grep to test/fresh-home.sh, and empties or drops each extras row's cells,
# one mutation at a time, and expects lint to fail naming the mutated text.
# Passes when every mutation is caught. Run by CI after test/lint.sh.
set -euo pipefail

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
COPY="$(mktemp -d)"
trap 'rm -rf "$COPY"' EXIT

# The working tree, as fresh-home.sh copies it. Mutations are made here only.
copy_worktree "$REPO_DIR" "$COPY"

# The copy has only a snapshot commit to scan; lint scans the real repo.
lint() { (cd "$COPY" && LINT_SKIP_SECRETS=1 test/lint.sh 2>&1); }

lint >/dev/null || { lint >&2 || true; echo "FAIL: lint fails on the unmutated copy" >&2; exit 1; }

runs=0 survived=0
# mutate <file> <sed program> <description> <needle>...: applies the program
# to the copy's file, expects lint to fail naming one of the needles, then
# restores the file.
mutate() {
  local file="$1" program="$2" desc="$3" out needle
  shift 3
  runs=$((runs + 1))
  sed -i '' -E "$program" "$COPY/$file"
  if cmp -s "$REPO_DIR/$file" "$COPY/$file"; then
    echo "FAIL: mutation didn't change $file: $desc" >&2
    survived=$((survived + 1))
  elif out="$(lint)"; then
    echo "FAIL: lint let through: $desc" >&2
    survived=$((survived + 1))
  else
    for needle in "$@"; do
      [[ -n "$needle" && "$out" == *"$needle"* ]] && break
      needle=""
    done
    if [[ -z "$needle" ]]; then
      echo "FAIL: lint caught $desc, but its message names none of: $*" >&2
      echo "$out" >&2
      survived=$((survived + 1))
    fi
  fi
  cp "$REPO_DIR/$file" "$COPY/$file"
}

# Each marker removed. Lint names its line when another marker keeps the text,
# else the text through fresh-home.sh's grep: each fixed piece of a
# <placeholder> marker counts.
while IFS=: read -r file n code; do
  marker="$(sed -E 's/.*# fresh-home\.sh greps for "(.*)"$/\1/' <<<"$code")"
  pieces=()
  while IFS= read -r piece; do pieces+=("$piece"); done < <(sed -E 's/<[^>]+>/\n/g' <<<"$marker")
  mutate "$file" "${n}s/[[:space:]]*# fresh-home\\.sh greps for \".*\"\$//" \
    "marker removed at $file:$n" "$file:$n" ${pieces[@]+"${pieces[@]}"}
done < <(cd "$REPO_DIR" && grep -nF '# fresh-home.sh greps for "' install.sh doctor.sh lib/common.sh)

mutate lib/common.sh 's/# fresh-home\.sh greps for "optional extras"$/# fresh-home.sh greps for "lint-selftest reworded"/' \
  "marker reworded" "lint-selftest reworded"

mutate test/fresh-home.sh "\$a\\
grep -q 'lint-selftest unmarked' <<<\"\$doctor_out\" || die x
" "unmarked grep added to test/fresh-home.sh" "lint-selftest unmarked"

# Each extras row: its line cell emptied, its file cell emptied, its last cell
# dropped.
while IFS= read -r extra; do
  row="/^\\| \`${extra//\//\\/}\` /"
  mutate README.md "${row}s/^(.*\\| )\`[^\`]+\`( *\\| *\`[^\`]+\` *\\|[[:space:]]*)\$/\\1\\2/" \
    "README extras line cell emptied for $extra" "$extra"
  mutate README.md "${row}s/^(.*\\| *\`[^\`]+\` *\\| )\`[^\`]+\`( *\\|[[:space:]]*)\$/\\1\\2/" \
    "README extras file cell emptied for $extra" "$extra"
  mutate README.md "${row}s/^(.*\\|)[^|]+\\|[[:space:]]*\$/\\1/" \
    "README extras last cell dropped for $extra" "$extra"
done < <(cd "$REPO_DIR" && printf '%s\n' */extras/*)

if ((survived)); then
  echo "lint-selftest: $survived of $runs mutation(s) not caught" >&2
  exit 1
fi
echo "lint-selftest: ok ($runs mutations caught)"
