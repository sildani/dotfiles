#!/usr/bin/env bash
# Checks that test/lint.sh's marker, extras and test-script checks still catch
# what they exist for: in a copy of the working tree, it removes each
# `# fresh-home.sh greps for "<text>"` marker, rewords one, rewords a message
# under its marker, malforms one twice, drops one piece of a <placeholder>
# marker from test/fresh-home.sh, adds an unmarked grep and a negated [[ ]]
# test of script output there, adds a marker outside MARKER_FILES, empties or
# drops each extras row's cells, drops each test script's CI step and README
# "Checks" bullet, glues a # to a CI step,
# adds an unlisted test script, drops a flag from shrink's man page or
# completion, and drops an extension, a type and a PDF level from the
# completion. It makes one mutation at a time and expects lint to fail naming
# the mutated text. Also drops each test script's lib/test-guard.sh, runs the guard itself
# (also as CI on a bash other than /bin/bash),
# adds each multi-word _Avoid_ entry from GLOSSARY.md, checks that lint passes a
# CI step ending in a comment, and checks that lint as
# the commit hook runs it passes an untracked test script it isn't committing.
# Passes when every mutation is caught and every other check passes. Run by CI
# after test/lint.sh.
#
# The mutations and checks run in parallel workers, each in its own copy of the
# tree: LINT_SELFTEST_JOBS of them, by default half the Mac's cores, rounded
# up. Failures print in the same order whatever the worker count.

# One group, ended by exit: bash reads all of it before running any, so an
# edit to this file mid-run can't change the run.
# shellcheck disable=SC2329  # the queued items run through eval, cleanup through trap
{
set -euo pipefail
# shellcheck source=lib/test-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-guard.sh"

# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

workers="${LINT_SELFTEST_JOBS:-$((($(sysctl -n hw.ncpu) + 1) / 2))}"
[[ "$workers" =~ ^[1-9][0-9]*$ ]] || { echo "FAIL: LINT_SELFTEST_JOBS must be a positive integer, not '$workers'" >&2; exit 1; }

# Everything the run writes, the snapshot and each worker's copy included.
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lint-selftest.XXXXXX")"
SNAP="$ROOT/snap"
pids=()
# kill_tree <pid>: the worker and the lint it's running. A background job
# ignores Ctrl-C, so the workers are stopped here.
kill_tree() {
  local kids kid
  kids="$(pgrep -P "$1" || true)"
  kill "$1" 2>/dev/null || true
  for kid in $kids; do kill_tree "$kid"; done
}
cleanup() {
  local pid
  for pid in ${pids[@]+"${pids[@]}"}; do kill_tree "$pid"; done
  wait 2>/dev/null || true
  rm -rf "${ROOT:?}"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# The working tree, as fresh-home.sh copies it, taken once: every read and
# restore after this uses the snapshot, so the repo can change mid-run.
# Mutations are made in the workers' copies only.
copy_worktree "$REPO_DIR" "$SNAP"
COPY="$ROOT/w0"
copy_worktree "$SNAP" "$COPY"
[[ -z "$(git -C "$COPY" status --porcelain)" ]] || { echo "FAIL: copy_worktree left the copy with changes" >&2; exit 1; }

# The copy has only a snapshot commit to scan; CI's test/lint.sh run scans the
# real repo's history.
lint() { (cd "$COPY" && LINT_SKIP_SECRETS=1 test/lint.sh 2>&1); }

lint >/dev/null || { lint >&2 || true; echo "FAIL: lint fails on the unmutated copy" >&2; exit 1; }

# The queue: each item is a mutation, which lint must catch, or one of the
# checks that aren't mutations (the guard's own behaviour, and lint passing
# where it should). An item runs in its worker's copy as COPY, prints only
# what fails, returns nonzero when it fails, and leaves the copy as it found it.
items=() kinds=()
# queue <mutation|check> <function> <arg>...
queue() {
  kinds+=("$1")
  shift
  items+=("$(printf '%q ' "$@")")
}

# expect_caught <description> <needle>...: expects lint to fail on the copy
# as it is now, naming one of the needles.
expect_caught() {
  local desc="$1" out needle
  shift
  if out="$(lint)"; then
    echo "FAIL: lint let through: $desc"
    return 1
  fi
  for needle in "$@"; do
    [[ -n "$needle" && "$out" == *"$needle"* ]] && return 0
  done
  echo "FAIL: lint caught $desc, but its message names none of: $*"
  echo "$out"
  return 1
}

# mutate <file> <sed program> <description> <needle>...: queues a mutation
# that applies the program to the copy's file, expects lint to fail naming one
# of the needles, then restores the file.
mutate() { queue mutation run_mutate "$@"; }
run_mutate() {
  local file="$1" program="$2" desc="$3" rc=0
  shift 3
  sed -i '' -E "$program" "$COPY/$file"
  if cmp -s "$SNAP/$file" "$COPY/$file"; then
    echo "FAIL: mutation didn't change $file: $desc"
    rc=1
  else
    expect_caught "$desc" "$@" || rc=1
  fi
  cp "$SNAP/$file" "$COPY/$file"
  return "$rc"
}

# append <file> <text> <description> <needle>...: queues a mutation that adds
# the text as a line at the end of the copy's file.
append() { queue mutation run_append "$@"; }
run_append() {
  local file="$1" text="$2" desc="$3" rc=0
  shift 3
  printf '%s\n' "$text" >>"$COPY/$file"
  expect_caught "$desc" "$@" || rc=1
  cp "$SNAP/$file" "$COPY/$file"
  return "$rc"
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
# The message reworded and its marker left as it was.
mutate test/nvim.sh 's/echo "test\/nvim\.sh: skipped,/echo "test\/nvim.sh: lint-selftest reworded,/' \
  "message reworded under its marker" "no longer prints \"test/nvim.sh: skipped\""

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
  echo "FAIL: no <placeholder> marker in ${MARKER_FILES[*]} to drop a piece of from test/fresh-home.sh" >&2
  exit 1
fi

mutate test/fresh-home.sh "\$a\\
grep -q 'lint-selftest unmarked' <<<\"\$doctor_out\" || die x
" "unmarked grep added to test/fresh-home.sh" "lint-selftest unmarked"
# The check test/nvim.sh's skip line had before #128, which passed quietly
# once the message was reworded.
mutate test/fresh-home.sh "\$a\\
[[ \"\$nvim_out\" != *\"test/nvim.sh: skipped\"* ]] || die \"nvim test skipped\"
" "negated [[ ]] test of script output in test/fresh-home.sh" "negates a [[ ]] test of script output"

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
  mutate .github/workflows/check.yml "/^[[:space:]]*-?[[:space:]]*run:[[:space:]]*${path_re}([[:space:]]+#.*|[[:space:]]*)\$/d" \
    "check.yml step dropped for $f" "$f"
  mutate README.md "/^- \`${path_re}\`:/d" "README Checks bullet dropped for $f" "$f"
done

# A CI step may end in a YAML comment, but # without a space before it is part
# of the command, so that step doesn't run the script.
step_re='^([[:space:]]*-?[[:space:]]*run:[[:space:]]*test/lint\.sh)[[:space:]]*$'
queue check check_ci_comment
check_ci_comment() {
  local out rc=0
  sed -i '' -E "s,$step_re,\\1  # lint-selftest comment," "$COPY/.github/workflows/check.yml"
  if cmp -s "$SNAP/.github/workflows/check.yml" "$COPY/.github/workflows/check.yml"; then
    echo "FAIL: no test/lint.sh step in check.yml to add a comment to"
    rc=1
  elif ! out="$(lint)"; then
    echo "FAIL: lint didn't pass a check.yml step that ends in a comment:"
    echo "$out"
    rc=1
  fi
  cp "$SNAP/.github/workflows/check.yml" "$COPY/.github/workflows/check.yml"
  return "$rc"
}
mutate .github/workflows/check.yml "s,$step_re,\\1#lint-selftest," \
  "check.yml step with # straight after the script" "doesn't run test/lint.sh"

# A marker in a file outside MARKER_FILES, which lint's other marker checks
# don't read.
mutate README.md "\$a\\
x  # fresh-home.sh greps for \"lint-selftest unlisted\"
" "marker outside MARKER_FILES" "isn't in MARKER_FILES"

# A test script without the guard, which would otherwise stop silently.
for f in "$SNAP"/test/*.sh; do
  f="test/${f##*/}"
  mutate "$f" '/^source .*lib\/test-guard\.sh/d' "no guard in $f" "$f doesn't source lib/test-guard.sh"
done

# The guard itself, on stock bash: it names a stop at the top level, and inside
# a function by its caller, and an expected failure stays quiet.
# check_guard <argument> <message>
check_guard() {
  local out rc=0
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
  out="$(/bin/bash "$COPY/guard-check.sh" "$1" 2>&1)" || rc=$?
  rm "${COPY:?}/guard-check.sh"
  if ((rc == 0)) || [[ "$out" != "$2" ]]; then
    echo "FAIL: the guard printed '$out' (exit $rc), not '$2'"
    return 1
  fi
}
queue check check_guard top "guard-check.sh: died at line 10: false"
queue check check_guard function "guard-check.sh: died in stops, called from line 11: false"

# The guard in CI, on a bash other than stock /bin/bash: it stops the test
# before it runs, so CI can't pass on a newer bash than a new Mac has.
check_guard_ci() {
  local out rc=0 want="guard-ci.sh: runs on /opt/homebrew/bin/bash, not stock /bin/bash; CI puts /bin first on PATH"
  cat >"$COPY/guard-ci.sh" <<GUARD
set -euo pipefail
BASH=/opt/homebrew/bin/bash
source "$SNAP/lib/test-guard.sh"
echo ran
GUARD
  out="$(CI=true /bin/bash "$COPY/guard-ci.sh" 2>&1)" || rc=$?
  rm "${COPY:?}/guard-ci.sh"
  if ((rc == 0)) || [[ "$out" != "$want" ]]; then
    echo "FAIL: the guard in CI on another bash printed '$out' (exit $rc), not '$want'"
    return 1
  fi
}
queue check check_guard_ci

# Each multi-word _Avoid_ entry, split over a commented line break, as wrapped
# text splits one. No entries would leave the check empty.
mutate GLOSSARY.md 's/^_Avoid_: .*//' "no _Avoid_ entries" "no multi-word _Avoid_ entries"
line_break=$'\n# '
while IFS= read -r phrase; do
  append README.md "${phrase/ /$line_break}" "_Avoid_ entry: $phrase" "$phrase"
done < <(avoid_phrases "$SNAP/GLOSSARY.md")

# A flag shrink's help lists, dropped from its man page or its completion:
# --fps, and -f, which lint mustn't find inside \-\-fps. Then an extension, a
# type and a PDF level dropped from the completion.
for flag in --fps -f; do
  man_flag="$(sed_literal "${flag//-/\\-}")"
  mutate man/shrink.1 "/(^|[^-])$man_flag([^a-z-]|\$)/d" "man page without $flag" "doesn't document $flag,"
  mutate zsh/completions/_shrink "/[')\"]$(sed_literal "$flag")\[/d" "completion without $flag" "doesn't complete $flag,"
done
mutate zsh/completions/_shrink 's/ heic / /' "completion without heic" "should list shrink's extensions"
mutate zsh/completions/_shrink 's/ image pdf\)$/ image)/' "completion without the pdf type" "should list shrink's types"
mutate zsh/completions/_shrink 's/ ebook / /' "completion without the ebook level" "should list shrink's PDF levels"

# A test script in neither list.
new_script=test/lint-selftest-new.sh
queue mutation run_unlisted_script
run_unlisted_script() {
  local rc=0
  printf '#!/usr/bin/env bash\ntrue\n' >"$COPY/$new_script"
  chmod +x "$COPY/$new_script"
  expect_caught "unlisted $new_script" "$new_script" || rc=1
  rm "${COPY:?}/${new_script:?}"
  return "$rc"
}
# The commit hook's lint lists test scripts from the index, so the same
# untracked script doesn't block a commit it isn't part of, even one that
# fails shellcheck.
queue check check_staged_lint
check_staged_lint() {
  local out rc=0
  # shellcheck disable=SC2016  # the error is for lint's shellcheck to find
  printf '#!/usr/bin/env bash\ntrue\n[ $lint_selftest_unset = x ]\n' >"$COPY/$new_script"
  chmod +x "$COPY/$new_script"
  if ! out="$(LINT_STAGED=1 lint)"; then
    echo "FAIL: lint with LINT_STAGED=1 failed on an untracked $new_script:"
    echo "$out"
    rc=1
  fi
  rm "${COPY:?}/${new_script:?}"
  return "$rc"
}

# The workers: worker k runs items k, k+workers, … in its own copy, and writes
# each item's output and result to files the summary reads in item order.
((workers <= ${#items[@]})) || workers=${#items[@]}
mkdir "$ROOT/out"
# run_worker <k>
run_worker() {
  local i rc
  COPY="$ROOT/w$1"
  for ((i = $1; i < ${#items[@]}; i += workers)); do
    rc=0
    eval "${items[i]}" >"$ROOT/out/$i" 2>&1 || rc=1
    if [[ -n "$(git -C "$COPY" status --porcelain)" ]]; then
      echo "FAIL: this item left its copy changed: ${items[i]}" >>"$ROOT/out/$i"
      git -C "$COPY" reset -q --hard
      git -C "$COPY" clean -qfd
      rc=1
    fi
    echo "$rc" >"$ROOT/out/$i.rc"
  done
}
for ((k = 1; k < workers; k++)); do copy_worktree "$SNAP" "$ROOT/w$k"; done
for ((k = 0; k < workers; k++)); do
  run_worker "$k" &
  pids+=("$!")
done
for pid in ${pids[@]+"${pids[@]}"}; do wait "$pid" || true; done
# Reaped, so cleanup mustn't kill their PIDs, which may belong to others now.
pids=()

mutations=0 survived=0 checks=0 failed=0
for ((i = 0; i < ${#items[@]}; i++)); do
  rc="$(cat "$ROOT/out/$i.rc" 2>/dev/null || echo missing)"
  [[ -f "$ROOT/out/$i" ]] && cat "$ROOT/out/$i" >&2
  [[ "$rc" == missing ]] && echo "FAIL: this item didn't finish: ${items[i]}" >&2
  if [[ "${kinds[i]}" == mutation ]]; then
    mutations=$((mutations + 1))
    [[ "$rc" == 0 ]] || survived=$((survived + 1))
  else
    checks=$((checks + 1))
    [[ "$rc" == 0 ]] || failed=$((failed + 1))
  fi
done

if ((survived || failed)); then
  echo "lint-selftest: $survived of $mutations mutation(s) not caught, $failed of $checks check(s) failed" >&2
  exit 1
fi
echo "lint-selftest: ok ($mutations mutations caught, $checks checks passed)"
exit
}
