#!/usr/bin/env bash
# Checks that test/lint.sh's marker, extras and test-script checks still catch
# what they exist for: in a copy of the working tree, it removes each
# `# fresh-home.sh greps for "<text>"` marker, rewords one, malforms one twice,
# drops one piece of a <placeholder> marker from test/fresh-home.sh, adds an
# unmarked grep there, empties or drops each extras row's cells, drops each
# test script's CI step and README "Checks" bullet, and adds an unlisted test
# script, one mutation at a time, and expects lint to fail naming the mutated
# text. Also drops each test script's lib/test-guard.sh, runs the guard itself,
# adds each multi-word _Avoid_ entry from GLOSSARY.md, and checks that lint as
# the commit hook runs it passes an untracked test script it isn't committing.
# Passes when every mutation is caught. Run by CI after test/lint.sh.

# One group, ended by exit: bash reads all of it before running any, so an
# edit to this file mid-run can't change the run.
{
set -euo pipefail
# shellcheck source=lib/test-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-guard.sh"

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
SNAP="$(mktemp -d)"
trap 'rm -rf "$SNAP" "${COPY-}"' EXIT
COPY="$(mktemp -d)"

# The working tree, as fresh-home.sh copies it, taken once: every read and
# restore after this uses the snapshot, so the repo can change mid-run.
# Mutations are made in the copy only.
copy_worktree "$REPO_DIR" "$SNAP"
copy_worktree "$SNAP" "$COPY"
[[ -z "$(git -C "$COPY" status --porcelain)" ]] || { echo "FAIL: copy_worktree left the copy with changes" >&2; exit 1; }

# The copy has only a snapshot commit to scan; CI's test/lint.sh run scans the
# real repo's history.
lint() { (cd "$COPY" && LINT_SKIP_SECRETS=1 test/lint.sh 2>&1); }

lint >/dev/null || { lint >&2 || true; echo "FAIL: lint fails on the unmutated copy" >&2; exit 1; }

runs=0 survived=0
# expect_caught <description> <needle>...: expects lint to fail on the copy
# as it is now, naming one of the needles.
expect_caught() {
  local desc="$1" out needle
  shift
  if out="$(lint)"; then
    echo "FAIL: lint let through: $desc" >&2
    survived=$((survived + 1))
    return
  fi
  for needle in "$@"; do
    [[ -n "$needle" && "$out" == *"$needle"* ]] && return
  done
  echo "FAIL: lint caught $desc, but its message names none of: $*" >&2
  echo "$out" >&2
  survived=$((survived + 1))
}

# mutate <file> <sed program> <description> <needle>...: applies the program
# to the copy's file, expects lint to fail naming one of the needles, then
# restores the file.
mutate() {
  local file="$1" program="$2" desc="$3"
  shift 3
  runs=$((runs + 1))
  sed -i '' -E "$program" "$COPY/$file"
  if cmp -s "$SNAP/$file" "$COPY/$file"; then
    echo "FAIL: mutation didn't change $file: $desc" >&2
    survived=$((survived + 1))
  else
    expect_caught "$desc" "$@"
  fi
  cp "$SNAP/$file" "$COPY/$file"
}

# sed_literal <text>: the text as a sed -E pattern that matches it literally,
# with `/` escaped for the s/// delimiter.
sed_literal() { sed -E 's#[][\/.^$*+?(){}|]#\\&#g' <<<"$1"; }

# Each marker removed. Lint names its line when another marker keeps the text,
# else the text through fresh-home.sh's grep: each fixed piece of a
# <placeholder> marker counts.
while IFS=: read -r file n code; do
  [[ "$code" =~ $MARKER_RE ]] || { echo "FAIL: $file:$n doesn't match MARKER_RE (lib/common.sh)" >&2; exit 1; }
  pieces=()
  while IFS= read -r piece; do pieces+=("$piece"); done < <(marker_pieces "${BASH_REMATCH[1]}")
  mutate "$file" "${n}s/[[:space:]]*${MARKER_RE}//" \
    "marker removed at $file:$n" "$file:$n" ${pieces[@]+"${pieces[@]}"}
done < <(cd "$SNAP" && grep -nF '# fresh-home.sh greps for "' "${MARKER_FILES[@]}")

mutate lib/common.sh 's/# fresh-home\.sh greps for "optional extras"$/# fresh-home.sh greps for "lint-selftest reworded"/' \
  "marker reworded" "lint-selftest reworded"

# Near-miss markers: joined to another comment, and with text after the quote.
line="$(grep -nF '# fresh-home.sh greps for "optional extras"' "$SNAP/lib/common.sh" | cut -d: -f1)"
mutate lib/common.sh 's/# fresh-home\.sh greps for "optional extras"$/# doctor-warnings.sh checks this text; fresh-home.sh greps for "optional extras"/' \
  "near-miss marker after another comment" "lib/common.sh:$line has a malformed marker"
mutate lib/common.sh 's/# fresh-home\.sh greps for "optional extras"$/# fresh-home.sh greps for "optional extras", too/' \
  "near-miss marker with text after it" "lib/common.sh:$line has a malformed marker"

# One piece of a <placeholder> marker gone from test/fresh-home.sh: the first
# fixed piece of the first such marker, so the target follows the markers.
piece=""
while IFS= read -r marker; do
  [[ "$marker" =~ $MARKER_PLACEHOLDER_RE ]] || continue
  IFS= read -r piece < <(marker_pieces "$marker") || true
  [[ -n "$piece" ]] && break
done < <(marker_texts "$SNAP")
if [[ -n "$piece" ]]; then
  mutate test/fresh-home.sh "s/$(sed_literal "$piece")/ lint-selftest piece /g" \
    "one piece of a <placeholder> marker gone from test/fresh-home.sh" "no longer greps for \"$piece\""
else
  runs=$((runs + 1)) survived=$((survived + 1))
  echo "FAIL: no <placeholder> marker in ${MARKER_FILES[*]} to drop a piece of from test/fresh-home.sh" >&2
fi

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
done < <(cd "$SNAP" && printf '%s\n' */extras/*)

# Each test script: its CI step dropped, its README "Checks" bullet dropped.
for f in "$SNAP"/test/*.sh; do
  f="test/${f##*/}"
  path_re="${f//./\\.}"
  path_re="${path_re//\//\\/}"
  mutate .github/workflows/check.yml "/^[[:space:]]*-?[[:space:]]*run:[[:space:]]*${path_re}[[:space:]]*\$/d" \
    "check.yml step dropped for $f" "$f"
  mutate README.md "/^- \`${path_re}\`:/d" "README Checks bullet dropped for $f" "$f"
done

# A test script without the guard, which would otherwise stop silently.
for f in "$SNAP"/test/*.sh; do
  f="test/${f##*/}"
  mutate "$f" '/^source .*lib\/test-guard\.sh/d' "no guard in $f" "$f doesn't source lib/test-guard.sh"
done

# The guard itself, on stock bash: it names a stop at the top level, and inside
# a function by its caller, and an expected failure stays quiet.
cat >"$COPY/guard-check.sh" <<GUARD
set -euo pipefail
source "$SNAP/lib/test-guard.sh"
fails() { false; }
out="\$(fails)" || true
if fails; then :; fi
stops() {
  :
  false
}
[ "\$1" = function ] || false
stops
GUARD
# expect_guard <argument> <message>
expect_guard() {
  local out rc=0
  runs=$((runs + 1))
  out="$(/bin/bash "$COPY/guard-check.sh" "$1" 2>&1)" || rc=$?
  if ((rc == 0)) || [[ "$out" != "$2" ]]; then
    echo "FAIL: the guard printed '$out' (exit $rc), not '$2'" >&2
    survived=$((survived + 1))
  fi
}
expect_guard top "guard-check.sh: died at line 10: false"
expect_guard function "guard-check.sh: died in stops, called from line 11: false"
rm "$COPY/guard-check.sh"

# Each multi-word _Avoid_ entry, split over a commented line break, as wrapped
# text splits one. No entries would leave the check empty.
mutate GLOSSARY.md 's/^_Avoid_: .*//' "no _Avoid_ entries" "no multi-word _Avoid_ entries"
line_break=$'\n# '
while IFS= read -r phrase; do
  runs=$((runs + 1))
  printf '%s\n' "${phrase/ /$line_break}" >>"$COPY/README.md"
  expect_caught "_Avoid_ entry: $phrase" "$phrase"
  cp "$SNAP/README.md" "$COPY/README.md"
done < <(avoid_phrases "$SNAP/GLOSSARY.md")

# A test script in neither list.
runs=$((runs + 1))
printf '#!/usr/bin/env bash\ntrue\n' >"$COPY/test/lint-selftest-new.sh"
chmod +x "$COPY/test/lint-selftest-new.sh"
expect_caught "unlisted test/lint-selftest-new.sh" test/lint-selftest-new.sh
# The commit hook's lint lists test scripts from the index, so the same
# untracked script doesn't block a commit it isn't part of, even one that
# fails shellcheck.
runs=$((runs + 1))
# shellcheck disable=SC2016  # the error is for lint's shellcheck to find
printf '[ $lint_selftest_unset = x ]\n' >>"$COPY/test/lint-selftest-new.sh"
if ! out="$(LINT_STAGED=1 lint)"; then
  echo "FAIL: lint with LINT_STAGED=1 failed on an untracked test/lint-selftest-new.sh:" >&2
  echo "$out" >&2
  survived=$((survived + 1))
fi
rm "$COPY/test/lint-selftest-new.sh"

if ((survived)); then
  echo "lint-selftest: $survived of $runs mutation(s) not caught" >&2
  exit 1
fi
echo "lint-selftest: ok ($runs mutations caught)"
exit
}
