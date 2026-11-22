#!/usr/bin/env bash
# Fast checks of bin/tidy-names, on stock bash, in temp directories: the Tidy
# name rules, -n, collisions, names that tidy to nothing, case-only renames,
# what a directory argument leaves alone, and help.
set -euo pipefail
# shellcheck source=lib/test-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-guard.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIDY="$REPO_DIR/bin/tidy-names"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
failed() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# fresh: an empty work directory, as $W.
fresh() { rm -rf "$TMP/w"; mkdir "$TMP/w"; W="$TMP/w"; }
# run [args...]: runs tidy-names in $W; sets out, errout and rc.
run() {
  rc=0
  (cd "$W" && /bin/bash "$TIDY" "$@") >"$TMP/out" 2>"$TMP/err" || rc=$?
  out="$(cat "$TMP/out")" errout="$(cat "$TMP/err")"
}
# listing [dir]: the names in dir (default $W), hidden ones too, one per line, sorted.
listing() {
  (shopt -s dotglob nullglob; for f in "${1:-$W}"/*; do echo "${f##*/}"; done) | LC_ALL=C sort
}

echo "a name with spaces, brackets and an upper-case extension"
fresh
touch "$W/My Report (Final) v2.PDF"
run
[[ "$(listing)" == "my-report-final-v2.pdf" ]] || failed "My Report (Final) v2.PDF became: $(listing)"
[[ "$out" == "My Report (Final) v2.PDF -> my-report-final-v2.pdf" ]] || failed "rename line: $out"
[[ $rc == 0 ]] || failed "exit $rc after a clean run"

echo "underscores, accents (precomposed and decomposed) and padded stems"
fresh
touch "$W/photo_2026_01.JPG" "$W/Café menu.txt" "$W/  notes  .md" "$W/$(printf 'Cafe\xcc\x81 bar.txt')" "$W/Ñandú.txt"
run
want=$'cafe-bar.txt\ncafe-menu.txt\nnandu.txt\nnotes.md\nphoto-2026-01.jpg'
[[ "$(listing)" == "$want" ]] || failed "tidied names:"$'\n'"$(listing)"
[[ "$out" == *"photo_2026_01.JPG -> photo-2026-01.jpg"* ]] || failed "no rename line for photo_2026_01.JPG: $out"
[[ $rc == 0 ]] || failed "exit $rc after a clean run"

echo "-n prints the same lines and renames nothing"
fresh
touch "$W/My Report (Final) v2.PDF" "$W/photo_2026_01.JPG"
run -n
[[ "$(listing)" == $'My Report (Final) v2.PDF\nphoto_2026_01.JPG' ]] || failed "-n renamed: $(listing)"
[[ "$out" == $'My Report (Final) v2.PDF -> my-report-final-v2.pdf\nphoto_2026_01.JPG -> photo-2026-01.jpg' ]] ||
  failed "-n printed: $out"
[[ $rc == 0 ]] || failed "-n exit $rc"

echo "an already-tidy file gives no output and exit 0"
fresh
touch "$W/notes.md"
run
[[ -z "$out$errout" && $rc == 0 ]] || failed "tidy file: out=[$out] err=[$errout] rc=$rc"

echo "a collision with an existing file skips the later one; the rest still go"
fresh
echo old >"$W/a-b.txt"
echo new >"$W/A B.txt"
touch "$W/C D.txt"
run
[[ "$(listing)" == $'A B.txt\na-b.txt\nc-d.txt' ]] || failed "existing collision left:"$'\n'"$(listing)"
[[ "$(cat "$W/a-b.txt")" == old ]] || failed "the existing a-b.txt was overwritten"
[[ "$errout" == *"A B.txt"* ]] || failed "the skipped A B.txt isn't named on stderr: $errout"
[[ $rc != 0 ]] || failed "exit 0 after a collision"
for flag in "" -n; do
  fresh
  echo first >"$W/a b.txt"
  echo second >"$W/a_b.txt"
  touch "$W/C D.txt"
  run ${flag:+"$flag"}
  [[ "$out" == $'C D.txt -> c-d.txt\na b.txt -> a-b.txt' ]] || failed "two files tidying to one name ($flag) printed: $out"
  [[ "$errout" == *"a_b.txt"* ]] || failed "the skipped a_b.txt isn't named on stderr ($flag): $errout"
  [[ $rc != 0 ]] || failed "exit 0 after two files tidying to one name ($flag)"
done
fresh
echo first >"$W/a b.txt"
echo second >"$W/a_b.txt"
run
[[ "$(listing)" == $'a-b.txt\na_b.txt' && "$(cat "$W/a-b.txt")" == first ]] ||
  failed "two files tidying to one name left:"$'\n'"$(listing)"

echo "names that tidy to nothing are skipped and reported"
fresh
touch "$W/日本.txt" "$W/???" "$W/Ok File.txt"
run
[[ "$(listing)" == $'???\nok-file.txt\n日本.txt' ]] || failed "tidy-to-nothing left:"$'\n'"$(listing)"
[[ "$errout" == *"日本.txt"* && "$errout" == *"???"* ]] || failed "tidy-to-nothing not reported: $errout"
[[ $rc != 0 ]] || failed "exit 0 after a name tidied to nothing"

echo "a change only in case is a rename"
fresh
touch "$W/README.md"
run
[[ "$(listing)" == readme.md && "$out" == "README.md -> readme.md" && $rc == 0 ]] ||
  failed "README.md: listing=$(listing) out=[$out] err=[$errout] rc=$rc"

echo "a directory argument leaves subdirectories, symlinks and hidden files alone"
fresh
mkdir "$W/Sub Dir" "$W/Other"
touch "$W/Sub Dir/Inner File.txt" "$W/Other/.Hidden File" "$W/Other/Top File.txt" "$W/target.txt"
ln -s ../target.txt "$W/Other/Link Name"
run Other
[[ "$(listing "$W/Other")" == $'.Hidden File\nLink Name\ntop-file.txt' ]] ||
  failed "Other/ left: $(listing "$W/Other")"
[[ "$out" == "Other/Top File.txt -> Other/top-file.txt" ]] || failed "directory argument printed: $out"
run
[[ -e "$W/Sub Dir/Inner File.txt" && -d "$W/Sub Dir" ]] || failed "tidy-names recursed into or renamed Sub Dir"
[[ $rc == 0 ]] || failed "exit $rc with a subdirectory and a symlink present"

echo "a file argument is tidied; a hidden file, a symlink or a missing path is not"
fresh
touch "$W/One File.txt" "$W/Two File.txt" "$W/.Hidden File" "$W/.hidden" "$W/target.txt"
ln -s target.txt "$W/Link Name"
run "One File.txt"
[[ "$out" == "One File.txt -> one-file.txt" && -e "$W/Two File.txt" && $rc == 0 ]] ||
  failed "file argument: out=[$out] rc=$rc listing=$(listing)"
for arg in ".Hidden File" .hidden "Link Name" "No Such File"; do
  run "$arg" "Two File.txt"
  [[ -e "$W/$arg" || "$arg" == "No Such File" ]] || failed "$arg was renamed"
  [[ "$errout" == *"$arg"* ]] || failed "$arg isn't named on stderr: $errout"
  [[ $rc != 0 ]] || failed "exit 0 after $arg"
  [[ -e "$W/two-file.txt" ]] || failed "Two File.txt wasn't tidied alongside $arg"
  [[ -e "$W/two-file.txt" ]] && mv "$W/two-file.txt" "$W/Two File.txt"
done

echo "-h prints the usage"
fresh
run -h
[[ "$out" == "usage: tidy-names [-n] [PATH...]"* && $rc == 0 ]] || failed "-h: out=[$out] rc=$rc"
run -x
[[ "$errout" == *"usage: tidy-names"* && $rc == 2 ]] || failed "-x: err=[$errout] rc=$rc"

if ((failures)); then
  echo "tidy-names: $failures failure(s)" >&2
  exit 1
fi
echo "tidy-names: ok"
