#!/usr/bin/env bash
# Fast checks of bin/shrink, on stock bash, against a fake ffmpeg and ffprobe on
# PATH: the commands it builds (seen through -n and the fake's log), naming,
# -o, -f, *.shrunk.* inputs, a result that isn't smaller, an interrupted run,
# the modification time, flag > SHRINK_* > default for every setting, the
# progress line, the HDR warning, a missing tool, an unsupported type, several
# files with one failing, and help.
set -euo pipefail
# shellcheck source=lib/test-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/test-guard.sh"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
failed() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# PROBE: the video stream the fake ffprobe describes (width,height,rate), and
# TRC its transfer function; it prints them as key=value lines, in ffprobe's
# own order, as the real one does whatever order they're asked for. OUT_BYTES: the size of what the fake ffmpeg writes. FFMPEG_MODE: ok, fail,
# or interrupt; each writes its output first, as a real one stopped midway
# does, and interrupt then signals shrink as Ctrl-C would.
export CALLS="$TMP/calls" PROBE TRC OUT_BYTES FFMPEG_MODE
mkdir "$TMP/bin" "$TMP/work"
cat >"$TMP/bin/ffprobe" <<'FAKE'
#!/bin/sh
echo "ffprobe $*" >>"$CALLS"
IFS=, read -r w h r <<EOF
$PROBE
EOF
printf 'width=%s\nheight=%s\ncolor_transfer=%s\navg_frame_rate=%s\n' "$w" "$h" "$TRC" "$r"
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
  out="$(cd "$TMP/work" && env -u SHRINK_CRF -u SHRINK_MAX_RES -u SHRINK_FPS -u SHRINK_AUDIO_BITRATE PATH="$TMP/bin:/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" "$@" 2>&1)" || rc=$?
}
# reset: an empty work folder and the fakes' defaults: a 1920x1080 30 fps SDR
# video that shrinks to 100 kB.
reset() {
  rm -rf "$TMP/work" && mkdir "$TMP/work"
  PROBE="1920,1080,30/1" TRC=bt709 OUT_BYTES=100000 FFMPEG_MODE=ok
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

echo "pixel format: 8-bit 4:2:0, so Apple's players open it, at even sizes"
reset
video odd.mov
PROBE="1281,721,30/1"
shrink odd.mov
[[ "$(ffmpeg_call)" == *"-pix_fmt yuv420p "* ]] || failed "ffmpeg wasn't given -pix_fmt yuv420p: $(ffmpeg_call)"
[[ "$(ffmpeg_call)" == *"-vf scale='trunc(iw/2)*2':'trunc(ih/2)*2' "* ]] ||
  failed "an odd-sized clip wasn't scaled to even sizes: $(ffmpeg_call)"

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

shrink -o newdir/ a.mov
[[ "$rc" != 0 && "$out" == *"no such folder"* ]] || failed "-o newdir/ didn't say there's no such folder: $out"

echo "two inputs with one output: the second is refused, even with -f"
reset
video a.mov
video a.mp4
shrink -f a.mov a.mp4
[[ "$rc" != 0 && "$out" == *"a.mov 1.0 MB → "* && "$out" == *"a.mp4: a.shrunk.mp4 was just made from another file"* ]] ||
  failed "a.mp4 replaced a.mov's copy in the same run: $out"

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

echo "video settings: --max-res, --fps and --audio-bitrate, each beating its SHRINK_* variable"
reset
video a.mov
shrink -n --max-res 720 a.mov
out="${out//\\/}"  # -n quotes for a shell
[[ "$rc" == 0 && "$out" == *"-vf scale='if(gt(iw,ih),-2,720)':'if(gt(iw,ih),720,-2)' "* ]] ||
  failed "--max-res 720 didn't cap a 1920x1080 clip's short side at 720: $out"
PROBE="1080,1920,30/1"
shrink -n --max-res 720 a.mov
out="${out//\\/}"
[[ "$out" == *"-vf scale='if(gt(iw,ih),-2,720)':'if(gt(iw,ih),720,-2)' "* ]] ||
  failed "--max-res 720 didn't cap a portrait clip's short side at 720: $out"
PROBE="1280,720,60/1"
shrink -n --fps 24 a.mov
[[ "$out" == *"-vf fps=24 "* ]] || failed "--fps 24 didn't cap a 60 fps clip at 24: $out"
PROBE="1280,720,15/1"
shrink -n --fps 24 a.mov
[[ "$out" != *fps=* ]] || failed "--fps 24 raised a 15 fps clip: $out"
reset
video a.mov
shrink -n --audio-bitrate 96k a.mov
[[ "$out" == *"-b:a 96k "* ]] || failed "--audio-bitrate 96k didn't reach ffmpeg: $out"
# setting <variable=value> <flag> <value> <want>: the variable alone gives
# want; with the flag too, the flag's value wins.
setting() {
  out="$(cd "$TMP/work" && env "$1" PATH="$TMP/bin:/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" -n a.mov 2>&1)"
  out="${out//\\/}"
  [[ "$out" == *"$4"* ]] || failed "$1 didn't give $4: $out"
  out="$(cd "$TMP/work" && env "$1" PATH="$TMP/bin:/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" -n "$2" "$3" a.mov 2>&1)"
  out="${out//\\/}"
  [[ "$out" != *"$4"* ]] || failed "$2 $3 didn't beat $1: $out"
}
PROBE="3840,2160,60/1"
setting SHRINK_MAX_RES=720 --max-res 480 "-2,720)"
setting SHRINK_FPS=24 --fps 25 "fps=24"
setting SHRINK_AUDIO_BITRATE=96k --audio-bitrate 64k "-b:a 96k "
for bad in "--max-res 0" "--max-res big" "--fps 0" "--fps x" "--audio-bitrate loud" "--audio-bitrate 96"; do
  # shellcheck disable=SC2086  # flag and value
  shrink -n $bad a.mov
  [[ "$rc" == 2 ]] || failed "$bad wasn't refused: rc $rc: $out"
done
rc=0
out="$(cd "$TMP/work" && env SHRINK_FPS=fast PATH="$TMP/bin:/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" -n a.mov 2>&1)" || rc=$?
[[ "$rc" == 2 && "$out" == *SHRINK_FPS* ]] || failed "SHRINK_FPS=fast wasn't refused by name: rc $rc: $out"

echo "progress: ffmpeg's progress line on a terminal, none when piped"
reset
video a.mov
shrink a.mov
[[ "$(ffmpeg_call)" == *" -nostats "* && "$(ffmpeg_call)" != *" -stats "* ]] ||
  failed "piped output didn't turn ffmpeg's progress off: $(ffmpeg_call)"
reset
video a.mov
rm -f "$CALLS"
(cd "$TMP/work" && env -u SHRINK_CRF PATH="$TMP/bin:/usr/bin:/bin" script -q /dev/null /bin/bash "$REPO_DIR/bin/shrink" a.mov </dev/null >/dev/null 2>&1) || true
[[ "$(ffmpeg_call)" == *" -stats "* ]] || failed "a terminal didn't get ffmpeg's progress line: $(ffmpeg_call)"
[[ -f "$TMP/work/a.shrunk.mp4" ]] || failed "the terminal run didn't shrink a.mov"

echo "HDR: PQ and HLG inputs are warned about on stderr, and still shrink"
for trc in smpte2084:PQ arib-std-b67:HLG; do
  reset
  video a.mov
  TRC="${trc%%:*}"
  rc=0
  err="$(cd "$TMP/work" && env -u SHRINK_CRF PATH="$TMP/bin:/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" a.mov 2>&1 >/dev/null)" || rc=$?
  [[ "$rc" == 0 && -f "$TMP/work/a.shrunk.mp4" ]] || failed "an HDR ($TRC) input didn't shrink: rc $rc: $err"
  [[ "$err" == "shrink: a.mov is HDR (${trc#*:}); the shrunk copy is standard range and will look washed out" ]] ||
    failed "no HDR (${trc#*:}) warning on stderr: $err"
  shrink -n -f a.mov
  [[ "$out" == *"is HDR (${trc#*:})"* ]] || failed "-n didn't show the HDR warning: $out"
done
reset
video a.mov
shrink a.mov
[[ "$out" != *HDR* ]] || failed "an SDR input got an HDR warning: $out"

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
for want in --crf SHRINK_CRF 23 --max-res SHRINK_MAX_RES 1080 --fps SHRINK_FPS 30 \
  --audio-bitrate SHRINK_AUDIO_BITRATE 128k ffmpeg HDR; do
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
