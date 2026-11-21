#!/usr/bin/env bash
# Fast checks of bin/shrink, on stock bash, against a fake ffmpeg and ffprobe on
# PATH: the commands it builds (seen through -n and the fake's log), naming,
# -o, -f, *.shrunk.* inputs, a result that isn't smaller, an interrupted run,
# the modification time, flag > SHRINK_* > default, a missing tool, an
# unsupported type, several files with one failing, and help.
set -euo pipefail
# shellcheck source=lib/test-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-guard.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
failed() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# PROBE: what the fake ffprobe prints for the video stream (width,height,rate).
# OUT_BYTES: the size of what the fake ffmpeg writes. FFMPEG_MODE: ok, fail,
# or interrupt; each writes its output first, as a real one stopped midway
# does, and interrupt then signals shrink as Ctrl-C would.
export CALLS="$TMP/calls" PROBE OUT_BYTES FFMPEG_MODE
mkdir "$TMP/bin" "$TMP/work"
cat >"$TMP/bin/ffprobe" <<'FAKE'
#!/bin/sh
echo "ffprobe $*" >>"$CALLS"
echo "$PROBE"
FAKE
# shellcheck disable=SC2016  # for the fake ffmpeg
cat >"$TMP/bin/ffmpeg" <<'FAKE'
#!/bin/sh
echo "ffmpeg $*" >>"$CALLS"
for a in "$@"; do out="$a"; done
head -c "$OUT_BYTES" /dev/zero >"$out"
[ "$FFMPEG_MODE" = fail ] && { echo "fake ffmpeg: failed" >&2; exit 1; }
if [ "$FFMPEG_MODE" = interrupt ]; then kill -INT "$PPID"; exit 255; fi
exit 0
FAKE
chmod +x "$TMP/bin/ffprobe" "$TMP/bin/ffmpeg"

# video <name> [bytes]: a fake input in the work folder, 1 MB unless given,
# with an old modification time.
video() {
  head -c "${2:-1000000}" /dev/zero >"$TMP/work/$1"
  touch -t 202001020304 "$TMP/work/$1"
}

# shrink <args>: runs bin/shrink in the work folder with the fakes and a
# defaults-only environment; sets out (stdout and stderr) and rc.
shrink() {
  rm -f "$CALLS"
  rc=0
  out="$(cd "$TMP/work" && env -u SHRINK_CRF PATH="$TMP/bin:/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" "$@" 2>&1)" || rc=$?
}
# reset: an empty work folder and the fakes' defaults: a 1920x1080 30 fps
# video that shrinks to 100 kB.
reset() {
  rm -rf "$TMP/work" && mkdir "$TMP/work"
  PROBE="1920,1080,30/1" OUT_BYTES=100000 FFMPEG_MODE=ok
}
ffmpeg_call() { grep '^ffmpeg ' "$CALLS" 2>/dev/null || true; }

echo "one video: a shrunk copy with the defaults, original untouched"
reset
video clip.mov
shrink clip.mov
[[ "$rc" == 0 ]] || failed "shrink clip.mov exited $rc: $out"
[[ -f "$TMP/work/clip.shrunk.mp4" ]] || failed "no clip.shrunk.mp4: $out"
[[ "$(stat -f %z "$TMP/work/clip.mov")" == 1000000 ]] || failed "the original changed size"
call="$(ffmpeg_call)"
for want in '-i clip.mov' '-c:v libx264' '-crf 23' '-c:a aac' '-b:a 128k' '-ac 2' '+faststart' '-map_metadata 0'; do
  [[ "$call" == *" $want"* ]] || failed "ffmpeg wasn't given $want: $call"
done
[[ "$call" != *scale* && "$call" != *fps* ]] || failed "a 1080p 30 fps video got a scale or fps filter: $call"
[[ "$out" == *"clip.mov 1.0 MB → 100 kB (-90%) → clip.shrunk.mp4"* ]] || failed "summary line: $out"

echo "caps: short side 1080, 30 fps"
reset
video portrait.mov
PROBE="1080,1920,30/1"
shrink portrait.mov
[[ "$(ffmpeg_call)" != *scale* ]] || failed "a 1080x1920 portrait clip got a scale filter: $(ffmpeg_call)"
video big.mov
PROBE="3840,2160,30/1"
shrink big.mov
[[ "$(ffmpeg_call)" == *"-vf scale='if(gt(iw,ih),-2,1080)':'if(gt(iw,ih),1080,-2)'"* ]] ||
  failed "a 3840x2160 clip wasn't scaled to a 1080 short side: $(ffmpeg_call)"
[[ "$(ffmpeg_call)" != *fps=* ]] || failed "a 30 fps clip got an fps filter: $(ffmpeg_call)"
video fast.mov
PROBE="1280,720,60000/1001"
shrink fast.mov
[[ "$(ffmpeg_call)" == *"-vf fps=30 "* ]] || failed "a 59.94 fps clip wasn't capped at 30: $(ffmpeg_call)"
PROBE="3840,2160,60/1"
shrink big.mov -f
[[ "$(ffmpeg_call)" == *"-vf scale='if(gt(iw,ih),-2,1080)':'if(gt(iw,ih),1080,-2)',fps=30 "* ]] ||
  failed "a 4K 60 fps clip didn't get both caps: $(ffmpeg_call)"

echo "the shrunk copy keeps the original's modification time, and no .part file is left"
reset
video clip.mov
shrink clip.mov
[[ "$(stat -f %m "$TMP/work/clip.shrunk.mp4")" == "$(stat -f %m "$TMP/work/clip.mov")" ]] ||
  failed "clip.shrunk.mp4's modification time isn't clip.mov's"
[[ -z "$(find "$TMP/work" -name '*.part')" ]] || failed "a .part file was left: $(ls -a "$TMP/work")"
[[ "$(ffmpeg_call)" == *" ./.clip.shrunk.mp4.part" ]] || failed "ffmpeg didn't write to a hidden .part file: $(ffmpeg_call)"

echo "several files: one line each; one failing makes the exit status non-zero"
reset
video a.mov
video b.MP4
video c.mkv
FFMPEG_MODE=ok
shrink a.mov notes.txt b.MP4 c.mkv
[[ "$rc" != 0 ]] || failed "an unsupported file left the exit status 0: $out"
[[ "$out" == *"notes.txt: unsupported type"* ]] || failed "notes.txt wasn't reported as an unsupported type: $out"
for f in a b c; do
  [[ -f "$TMP/work/$f.shrunk.mp4" ]] || failed "$f wasn't shrunk alongside a failing file: $out"
done
[[ "$(grep -c ' → ' <<<"$out")" == 3 ]] || failed "expected 3 summary lines: $out"
reset
video a.mov
FFMPEG_MODE=fail
shrink a.mov
[[ "$rc" != 0 && ! -e "$TMP/work/a.shrunk.mp4" ]] || failed "a failing ffmpeg left rc $rc or an output: $out"
[[ -z "$(find "$TMP/work" -name '*.part')" ]] || failed "a failing ffmpeg left a .part file"
shrink notes.txt
[[ "$rc" != 0 && "$out" == *"unsupported type"* ]] || failed "shrink notes.txt: rc $rc: $out"

echo "-o: a folder, a file name for one input, and no format change"
reset
video a.mov
video b.mov
mkdir "$TMP/work/out"
shrink -o out a.mov b.mov
[[ "$rc" == 0 && -f "$TMP/work/out/a.shrunk.mp4" && -f "$TMP/work/out/b.shrunk.mp4" ]] ||
  failed "-o out didn't put both copies in out/: $out"
shrink -o small.MP4 a.mov
[[ "$rc" == 0 && -f "$TMP/work/small.MP4" ]] || failed "-o small.MP4 for one input didn't write it: $out"
shrink -o clip.webm a.mov
[[ "$rc" != 0 && ! -e "$TMP/work/clip.webm" && "$out" == *".mp4"* ]] || failed "-o clip.webm wasn't refused: $out"
shrink -o two.mp4 a.mov b.mov
[[ "$rc" != 0 && ! -e "$TMP/work/two.mp4" ]] || failed "-o with a file name and two inputs wasn't refused: $out"
video a.mp4
shrink -o a.mp4 a.mp4 -f
[[ "$rc" != 0 && "$(stat -f %z "$TMP/work/a.mp4")" == 1000000 ]] || failed "-o onto the input wasn't refused: $out"

echo "-f: an existing output is refused without it and replaced with it"
reset
video a.mov
echo old >"$TMP/work/a.shrunk.mp4"
shrink a.mov
[[ "$rc" != 0 && "$(cat "$TMP/work/a.shrunk.mp4")" == old && "$out" == *"-f"* ]] ||
  failed "an existing output wasn't refused without -f: $out"
shrink -f a.mov
[[ "$rc" == 0 && "$(stat -f %z "$TMP/work/a.shrunk.mp4")" == 100000 ]] || failed "-f didn't replace the output: $out"

echo "*.shrunk.* inputs are skipped without -f"
reset
video a.shrunk.mp4
shrink a.shrunk.mp4
[[ "$rc" == 0 && "$out" == *skipped* && -z "$(ffmpeg_call)" ]] || failed "a.shrunk.mp4 wasn't skipped: $out"
shrink -f a.shrunk.mp4
[[ "$rc" == 0 && -f "$TMP/work/a.shrunk.shrunk.mp4" ]] || failed "-f didn't shrink a.shrunk.mp4: $out"

echo "a result that isn't smaller is deleted and reported"
reset
video a.mov
OUT_BYTES=1000000
shrink a.mov
[[ "$rc" == 0 && ! -e "$TMP/work/a.shrunk.mp4" && "$out" == *"wasn't smaller"* ]] ||
  failed "a result as big as the input wasn't deleted and reported: $out"
[[ -z "$(find "$TMP/work" -name '*.part')" ]] || failed "a not-smaller result left a .part file"

echo "an interrupted run leaves no output"
reset
video a.mov
FFMPEG_MODE=interrupt
shrink a.mov
[[ "$rc" != 0 ]] || failed "an interrupted run exited 0: $out"
[[ "$(ls -A "$TMP/work")" == a.mov ]] || failed "an interrupted run left files: $(ls -A "$TMP/work")"

echo "-n prints the commands and runs nothing"
reset
video a.mov
shrink -n a.mov
[[ "$rc" == 0 && "$(ls -A "$TMP/work")" == a.mov && -z "$(ffmpeg_call)" ]] || failed "-n ran something: $out"
[[ "$out" == *"ffmpeg "*"-i a.mov"*"./.a.shrunk.mp4.part"* && "$out" == *"touch -r a.mov ./.a.shrunk.mp4.part"* && "$out" == *"mv -f ./.a.shrunk.mp4.part a.shrunk.mp4"* ]] ||
  failed "-n didn't print the commands: $out"

echo "settings: a flag beats SHRINK_CRF, which beats the default"
reset
video a.mov
shrink -n a.mov
[[ "$out" == *"-crf 23 "* ]] || failed "default crf isn't 23: $out"
SHRINK_CRF=28
export SHRINK_CRF
out="$(cd "$TMP/work" && PATH="$TMP/bin:/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" -n a.mov 2>&1)"
[[ "$out" == *"-crf 28 "* ]] || failed "SHRINK_CRF=28 didn't set crf: $out"
out="$(cd "$TMP/work" && PATH="$TMP/bin:/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" -n --crf 30 a.mov 2>&1)"
[[ "$out" == *"-crf 30 "* ]] || failed "--crf 30 didn't beat SHRINK_CRF=28: $out"
unset SHRINK_CRF
shrink --crf 99 a.mov
[[ "$rc" == 2 ]] || failed "--crf 99 wasn't refused: $out"

echo "a missing ffmpeg is named, with install.sh"
reset
video a.mov
rc=0
out="$(cd "$TMP/work" && PATH="/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" a.mov 2>&1)" || rc=$?
[[ "$rc" != 0 && "$out" == *ffmpeg* && "$out" == *install.sh* ]] || failed "missing ffmpeg: rc $rc: $out"

echo "help: -h is short; --help video lists every setting"
shrink -h
[[ "$rc" == 0 && "$(wc -l <<<"$out")" -le 12 && "$out" == *usage:* ]] || failed "-h isn't a short usage screen: $out"
shrink --help video
for want in --crf SHRINK_CRF 23 128k 1080 30 ffmpeg; do
  [[ "$out" == *"$want"* ]] || failed "--help video doesn't mention $want: $out"
done
help_video="$out"
shrink --help
[[ "$out" == *"$help_video"* ]] || failed "--help doesn't include the video settings: $out"

if ((failures)); then
  echo "shrink: $failures failure(s)" >&2
  exit 1
fi
echo "shrink: ok"
