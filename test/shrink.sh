#!/usr/bin/env bash
# Fast checks of bin/shrink, on stock bash, against a fake ffmpeg, ffprobe,
# magick and pngquant on PATH: the commands it builds (seen through -n and the fake's log), naming,
# -o, -f, *.shrunk.* inputs, a result that isn't smaller, an interrupted run,
# the modification time, flag > SHRINK_* > default for every setting, the
# progress line, the HDR warning, images (names, settings, the EXIF chunk
# pngquant drops), a missing tool, an unsupported type, several files with one
# failing, and help.
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
# own order, as the real one does whatever order they're asked for.
# OUT_BYTES: the size of what the fake ffmpeg writes. FFMPEG_MODE: ok, fail,
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

# png <file> [chunk type and data...]: a small PNG (signature, IHDR, the given
# chunks, IDAT, IEND); CRCs are zeros, which shrink never checks.
png() {
  local f="$1" type data
  shift
  {
    printf '\211PNG\r\n\032\n'
    printf '\0\0\0\015IHDR\0\0\0\001\0\0\0\001\010\002\0\0\0\0\0\0\0'
    while (($#)); do
      type="$1" data="$2"
      shift 2
      printf "\\0\\0\\0\\$(printf %03o ${#data})%s%s\\0\\0\\0\\0" "$type" "$data"
    done
    printf '\0\0\0\003IDATabc\0\0\0\0\0\0\0\0IEND\0\0\0\0'
  } >"$f"
}
# The fake magick writes a PNG carrying EXIF (an eXIf chunk) when asked for
# png:, as the real one keeps it, and OUT_BYTES of zeros otherwise. The fake
# pngquant writes a PNG without it, as the real one drops it on a Mac.
png "$TMP/with-exif.png" eXIf "MM*EXIF" tEXt "k=v"
png "$TMP/quantized.png" PLTE "rgb" tEXt "k=v"
# Real image data follows the EXIF, more than a pipe holds.
head -c 300000 /dev/zero >>"$TMP/with-exif.png"
export WITH_EXIF="$TMP/with-exif.png" QUANTIZED="$TMP/quantized.png"
# shellcheck disable=SC2016  # for the fakes
cat >"$TMP/bin/magick" <<'FAKE'
#!/bin/sh
echo "magick $*" >>"$CALLS"
for a in "$@"; do out="$a"; done
case "$out" in
  png:*) cp "$WITH_EXIF" "${out#png:}" ;;
  *) head -c "$OUT_BYTES" /dev/zero >"${out#*:}" ;;
esac
FAKE
# shellcheck disable=SC2016
cat >"$TMP/bin/pngquant" <<'FAKE'
#!/bin/sh
echo "pngquant $*" >>"$CALLS"
while [ $# -gt 0 ]; do [ "$1" = --output ] && out="$2"; shift; done
cp "$QUANTIZED" "$out"
FAKE
chmod +x "$TMP/bin/ffprobe" "$TMP/bin/ffmpeg" "$TMP/bin/magick" "$TMP/bin/pngquant"

# without <tool>: a PATH folder with every fake but that one.
without() {
  rm -rf "$TMP/without" && mkdir "$TMP/without"
  for f in "$TMP"/bin/*; do [[ "$f" == */"$1" ]] || ln -s "$f" "$TMP/without/"; done
}

# input <name> [bytes]: a fake input of any type in the work folder, 1 MB
# unless given, with an old modification time.
input() {
  head -c "${2:-1000000}" /dev/zero >"$TMP/work/$1"
  touch -t 202001020304 "$TMP/work/$1"
}

# clean: env with no SHRINK_* setting from the caller's shell and the fakes
# first on PATH. A test's own VAR=value goes after it.
clean=(env -u SHRINK_CRF -u SHRINK_MAX_RES -u SHRINK_FPS -u SHRINK_AUDIO_BITRATE -u SHRINK_MAX_EDGE -u SHRINK_QUALITY PATH="$TMP/bin:/usr/bin:/bin")

# shrink <args>: runs bin/shrink in the work folder with the fakes and a
# defaults-only environment; sets out (stdout and stderr) and rc.
shrink() {
  rm -f "$CALLS"
  rc=0
  out="$(cd "$TMP/work" && "${clean[@]}" /bin/bash "$REPO_DIR/bin/shrink" "$@" 2>&1)" || rc=$?
}
# reset: an empty work folder and the fakes' defaults: a 1920x1080 30 fps SDR
# video that shrinks to 100 kB.
reset() {
  rm -rf "$TMP/work" && mkdir "$TMP/work"
  PROBE="1920,1080,30/1" TRC=bt709 OUT_BYTES=100000 FFMPEG_MODE=ok
}
ffmpeg_call() { grep '^ffmpeg ' "$CALLS" 2>/dev/null || true; }
# call <tool> <input>: the tool's logged call for that input.
call() { grep "^$1 .*$2" "$CALLS" 2>/dev/null || true; }

echo "one video: a shrunk copy with the defaults, original untouched"
reset
input clip.mov
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
input portrait.mov
PROBE="1080,1920,30/1"
shrink portrait.mov
[[ "$(ffmpeg_call)" != *scale* ]] || failed "a 1080x1920 portrait clip got a scale filter: $(ffmpeg_call)"
input big.mov
PROBE="3840,2160,30/1"
shrink big.mov
[[ "$(ffmpeg_call)" == *"-vf scale='if(gt(iw,ih),-2,1080)':'if(gt(iw,ih),1080,-2)'"* ]] ||
  failed "a 3840x2160 clip wasn't scaled to a 1080 short side: $(ffmpeg_call)"
[[ "$(ffmpeg_call)" != *fps=* ]] || failed "a 30 fps clip got an fps filter: $(ffmpeg_call)"
input fast.mov
PROBE="1280,720,60000/1001"
shrink fast.mov
[[ "$(ffmpeg_call)" == *"-vf fps=30 "* ]] || failed "a 59.94 fps clip wasn't capped at 30: $(ffmpeg_call)"
PROBE="3840,2160,60/1"
shrink big.mov -f
[[ "$(ffmpeg_call)" == *"-vf scale='if(gt(iw,ih),-2,1080)':'if(gt(iw,ih),1080,-2)',fps=30 "* ]] ||
  failed "a 4K 60 fps clip didn't get both caps: $(ffmpeg_call)"

echo "pixel format: 8-bit 4:2:0, so Apple's players open it, at even sizes"
reset
input odd.mov
PROBE="1281,721,30/1"
shrink odd.mov
[[ "$(ffmpeg_call)" == *"-pix_fmt yuv420p "* ]] || failed "ffmpeg wasn't given -pix_fmt yuv420p: $(ffmpeg_call)"
[[ "$(ffmpeg_call)" == *"-vf scale='trunc(iw/2)*2':'trunc(ih/2)*2' "* ]] ||
  failed "an odd-sized clip wasn't scaled to even sizes: $(ffmpeg_call)"

echo "the shrunk copy keeps the original's modification time, and no .part file is left"
reset
input clip.mov
shrink clip.mov
[[ "$(stat -f %m "$TMP/work/clip.shrunk.mp4")" == "$(stat -f %m "$TMP/work/clip.mov")" ]] ||
  failed "clip.shrunk.mp4's modification time isn't clip.mov's"
[[ -z "$(find "$TMP/work" -name '*.part')" ]] || failed "a .part file was left: $(ls -a "$TMP/work")"
[[ "$(ffmpeg_call)" == *" ./.clip.shrunk.mp4.part" ]] || failed "ffmpeg didn't write to a hidden .part file: $(ffmpeg_call)"

echo "several files: one line each; one failing makes the exit status non-zero"
reset
input a.mov
input b.MP4
input c.mkv
FFMPEG_MODE=ok
shrink a.mov notes.txt b.MP4 c.mkv
[[ "$rc" != 0 ]] || failed "an unsupported file left the exit status 0: $out"
[[ "$out" == *"notes.txt: unsupported type"* ]] || failed "notes.txt wasn't reported as an unsupported type: $out"
for f in a b c; do
  [[ -f "$TMP/work/$f.shrunk.mp4" ]] || failed "$f wasn't shrunk alongside a failing file: $out"
done
[[ "$(grep -c ' → ' <<<"$out")" == 3 ]] || failed "expected 3 summary lines: $out"
reset
input a.mov
FFMPEG_MODE=fail
shrink a.mov
[[ "$rc" != 0 && ! -e "$TMP/work/a.shrunk.mp4" ]] || failed "a failing ffmpeg left rc $rc or an output: $out"
[[ -z "$(find "$TMP/work" -name '*.part')" ]] || failed "a failing ffmpeg left a .part file"
shrink notes.txt
[[ "$rc" != 0 && "$out" == *"unsupported type"* ]] || failed "shrink notes.txt: rc $rc: $out"

echo "-o: a folder, a file name for one input, and no format change"
reset
input a.mov
input b.mov
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
input a.mp4
shrink -o a.mp4 a.mp4 -f
[[ "$rc" != 0 && "$(stat -f %z "$TMP/work/a.mp4")" == 1000000 ]] || failed "-o onto the input wasn't refused: $out"

shrink -o newdir/ a.mov
[[ "$rc" != 0 && "$out" == *"no such folder"* ]] || failed "-o newdir/ didn't say there's no such folder: $out"

echo "two inputs with one output: the second is refused, even with -f"
reset
input a.mov
input a.mp4
shrink -f a.mov a.mp4
[[ "$rc" != 0 && "$out" == *"a.mov 1.0 MB → "* && "$out" == *"a.mp4: a.shrunk.mp4 was just made from another file"* ]] ||
  failed "a.mp4 replaced a.mov's copy in the same run: $out"

echo "-f: an existing output is refused without it and replaced with it"
reset
input a.mov
echo old >"$TMP/work/a.shrunk.mp4"
shrink a.mov
[[ "$rc" != 0 && "$(cat "$TMP/work/a.shrunk.mp4")" == old && "$out" == *"-f"* ]] ||
  failed "an existing output wasn't refused without -f: $out"
shrink -f a.mov
[[ "$rc" == 0 && "$(stat -f %z "$TMP/work/a.shrunk.mp4")" == 100000 ]] || failed "-f didn't replace the output: $out"

echo "*.shrunk.* inputs are skipped without -f"
reset
input a.shrunk.mp4
shrink a.shrunk.mp4
[[ "$rc" == 0 && "$out" == *skipped* && -z "$(ffmpeg_call)" ]] || failed "a.shrunk.mp4 wasn't skipped: $out"
shrink -f a.shrunk.mp4
[[ "$rc" == 0 && -f "$TMP/work/a.shrunk.shrunk.mp4" ]] || failed "-f didn't shrink a.shrunk.mp4: $out"

echo "a result that isn't smaller is deleted and reported"
reset
input a.mov
OUT_BYTES=1000000
shrink a.mov
[[ "$rc" == 0 && ! -e "$TMP/work/a.shrunk.mp4" && "$out" == *"wasn't smaller"* ]] ||
  failed "a result as big as the input wasn't deleted and reported: $out"
[[ -z "$(find "$TMP/work" -name '*.part')" ]] || failed "a not-smaller result left a .part file"

echo "an interrupted run leaves no output"
reset
input a.mov
FFMPEG_MODE=interrupt
shrink a.mov
[[ "$rc" != 0 ]] || failed "an interrupted run exited 0: $out"
[[ "$(ls -A "$TMP/work")" == a.mov ]] || failed "an interrupted run left files: $(ls -A "$TMP/work")"

echo "-n prints the commands and runs nothing"
reset
input a.mov
shrink -n a.mov
[[ "$rc" == 0 && "$(ls -A "$TMP/work")" == a.mov && -z "$(ffmpeg_call)" ]] || failed "-n ran something: $out"
[[ "$out" == *"ffmpeg "*"-i a.mov"*"./.a.shrunk.mp4.part"* && "$out" == *"touch -r a.mov ./.a.shrunk.mp4.part"* && "$out" == *"mv -f ./.a.shrunk.mp4.part a.shrunk.mp4"* ]] ||
  failed "-n didn't print the commands: $out"

echo "settings: a flag beats SHRINK_CRF, which beats the default"
reset
input a.mov
shrink -n a.mov
[[ "$out" == *"-crf 23 "* ]] || failed "default crf isn't 23: $out"
out="$(cd "$TMP/work" && "${clean[@]}" SHRINK_CRF=28 /bin/bash "$REPO_DIR/bin/shrink" -n a.mov 2>&1)"
[[ "$out" == *"-crf 28 "* ]] || failed "SHRINK_CRF=28 didn't set crf: $out"
out="$(cd "$TMP/work" && "${clean[@]}" SHRINK_CRF=28 /bin/bash "$REPO_DIR/bin/shrink" -n --crf 30 a.mov 2>&1)"
[[ "$out" == *"-crf 30 "* ]] || failed "--crf 30 didn't beat SHRINK_CRF=28: $out"
shrink --crf 99 a.mov
[[ "$rc" == 2 ]] || failed "--crf 99 wasn't refused: $out"

echo "video settings: --max-res, --fps and --audio-bitrate, each beating its SHRINK_* variable"
reset
input a.mov
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
input a.mov
shrink -n --audio-bitrate 96k a.mov
[[ "$out" == *"-b:a 96k "* ]] || failed "--audio-bitrate 96k didn't reach ffmpeg: $out"
# setting <variable=value> <flag> <value> <want>: the variable alone gives
# want; with the flag too, the flag's value wins.
setting() {
  out="$(cd "$TMP/work" && "${clean[@]}" "$1" /bin/bash "$REPO_DIR/bin/shrink" -n a.mov 2>&1)"
  out="${out//\\/}"
  [[ "$out" == *"$4"* ]] || failed "$1 didn't give $4: $out"
  out="$(cd "$TMP/work" && "${clean[@]}" "$1" /bin/bash "$REPO_DIR/bin/shrink" -n "$2" "$3" a.mov 2>&1)"
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
out="$(cd "$TMP/work" && "${clean[@]}" SHRINK_FPS=fast /bin/bash "$REPO_DIR/bin/shrink" -n a.mov 2>&1)" || rc=$?
[[ "$rc" == 2 && "$out" == *SHRINK_FPS* ]] || failed "SHRINK_FPS=fast wasn't refused by name: rc $rc: $out"

echo "progress: ffmpeg's progress line on a terminal, none when piped"
reset
input a.mov
shrink a.mov
[[ "$(ffmpeg_call)" == *" -nostats "* && "$(ffmpeg_call)" != *" -stats "* ]] ||
  failed "piped output didn't turn ffmpeg's progress off: $(ffmpeg_call)"
reset
input a.mov
rm -f "$CALLS"
(cd "$TMP/work" && "${clean[@]}" script -q /dev/null /bin/bash "$REPO_DIR/bin/shrink" a.mov </dev/null >/dev/null 2>&1) || true
[[ "$(ffmpeg_call)" == *" -stats "* ]] || failed "a terminal didn't get ffmpeg's progress line: $(ffmpeg_call)"
[[ -f "$TMP/work/a.shrunk.mp4" ]] || failed "the terminal run didn't shrink a.mov"

echo "HDR: PQ and HLG inputs are warned about on stderr, and still shrink"
for trc in smpte2084:PQ arib-std-b67:HLG; do
  reset
  input a.mov
  TRC="${trc%%:*}"
  rc=0
  err="$(cd "$TMP/work" && "${clean[@]}" /bin/bash "$REPO_DIR/bin/shrink" a.mov 2>&1 >/dev/null)" || rc=$?
  [[ "$rc" == 0 && -f "$TMP/work/a.shrunk.mp4" ]] || failed "an HDR ($TRC) input didn't shrink: rc $rc: $err"
  [[ "$err" == "shrink: a.mov is HDR (${trc#*:}); the shrunk copy is standard range and will look washed out" ]] ||
    failed "no HDR (${trc#*:}) warning on stderr: $err"
  shrink -n -f a.mov
  [[ "$out" == *"is HDR (${trc#*:})"* ]] || failed "-n didn't show the HDR warning: $out"
done
reset
input a.mov
shrink a.mov
[[ "$out" != *HDR* ]] || failed "an SDR input got an HDR warning: $out"

echo "images: same format, except HEIC and TIFF become JPEG"
reset
for f in a.jpg b.png c.HEIC d.tiff e.webp; do input "$f"; done
shrink a.jpg b.png c.HEIC d.tiff e.webp
[[ "$rc" == 0 ]] || failed "shrinking five images exited $rc: $out"
for f in a.shrunk.jpg b.shrunk.png c.shrunk.jpg d.shrunk.jpg e.shrunk.webp; do
  [[ -f "$TMP/work/$f" ]] || failed "no $f: $(ls "$TMP/work")"
done
[[ "$(find "$TMP/work" -type f | wc -l | tr -d ' ')" == 10 ]] || failed "expected 5 inputs and 5 copies: $(ls -A "$TMP/work")"
[[ "$(call magick a.jpg)" == "magick a.jpg -resize 2560x2560> -quality 80 jpg:./.a.shrunk.jpg.part" ]] ||
  failed "JPEG: magick call: $(call magick a.jpg)"
[[ "$(call magick c.HEIC)" == "magick c.HEIC -resize 2560x2560> -quality 80 jpg:./.c.shrunk.jpg.part" ]] ||
  failed "HEIC: magick call (no rotating): $(call magick c.HEIC)"
[[ "$(call magick e.webp)" == "magick e.webp -resize 2560x2560> -quality 80 webp:./.e.shrunk.webp.part" ]] ||
  failed "WebP: magick call: $(call magick e.webp)"
# TIFF keeps its orientation in a tag a JPEG can't carry, so it's turned upright.
[[ "$(call magick d.tiff)" == "magick d.tiff -auto-orient -resize 2560x2560> -quality 80 jpg:./.d.shrunk.jpg.part" ]] ||
  failed "TIFF: magick call: $(call magick d.tiff)"
[[ "$(call pngquant b.shrunk)" == "pngquant --quality=0-80 --force --output ./.b.shrunk.png.part ./.b.shrunk.png.part.png" ]] ||
  failed "PNG: pngquant call: $(call pngquant b.shrunk)"
[[ "$(call magick b.png)" == "magick b.png -resize 2560x2560> png:./.b.shrunk.png.part.png" ]] ||
  failed "PNG: magick call: $(call magick b.png)"
[[ "$(head -c 41 "$TMP/work/b.shrunk.png" | tail -c 4)" == eXIf ]] ||
  failed "the shrunk PNG lost the EXIF chunk pngquant drops: $(od -c "$TMP/work/b.shrunk.png" | head -3)"
[[ "$(LC_ALL=C grep -c PLTE "$TMP/work/b.shrunk.png")" == 1 ]] || failed "the shrunk PNG isn't pngquant's"
[[ -z "$(find "$TMP/work" -name '*.part*')" ]] || failed "an image left a .part file: $(ls -A "$TMP/work")"
input photo.JPG
shrink photo.JPG
[[ -f "$TMP/work/photo.shrunk.JPG" ]] || failed "photo.JPG didn't become photo.shrunk.JPG: $out"

echo "images: -o follows the output format"
reset
input c.HEIC
shrink -o x.png c.HEIC
[[ "$rc" != 0 && ! -e "$TMP/work/x.png" && "$out" == *".jpg"* ]] || failed "-o x.png for a HEIC wasn't refused: $out"
shrink -o x.jpeg c.HEIC
[[ "$rc" == 0 && -f "$TMP/work/x.jpeg" ]] || failed "-o x.jpeg for a HEIC didn't write it: $out"
input b.png
shrink -o y.jpg b.png
[[ "$rc" != 0 && "$out" == *".png"* ]] || failed "-o y.jpg for a PNG wasn't refused: $out"

echo "image settings: --quality and --max-edge, each beating its SHRINK_* variable"
reset
input a.jpg
input b.png
shrink -n --quality 60 --max-edge 1000 a.jpg b.png
[[ "$out" == *"-resize 1000x1000\\> -quality 60 jpg:"* ]] || failed "--quality 60 --max-edge 1000 didn't reach magick: $out"
[[ "$out" == *"--quality=0-60 "* && "$out" == *"-resize 1000x1000\\> png:"* ]] ||
  failed "--quality 60 --max-edge 1000 didn't reach the PNG commands: $out"
# image_setting <variable=value> <flag> <value> <want>, as setting does for video.
image_setting() {
  out="$(cd "$TMP/work" && "${clean[@]}" "$1" /bin/bash "$REPO_DIR/bin/shrink" -n a.jpg 2>&1)"
  [[ "$out" == *"$4"* ]] || failed "$1 didn't give $4: $out"
  out="$(cd "$TMP/work" && "${clean[@]}" "$1" /bin/bash "$REPO_DIR/bin/shrink" -n "$2" "$3" a.jpg 2>&1)"
  [[ "$out" != *"$4"* ]] || failed "$2 $3 didn't beat $1: $out"
}
image_setting SHRINK_QUALITY=70 --quality 75 "-quality 70 "
image_setting SHRINK_MAX_EDGE=1200 --max-edge 900 "1200x1200"
for bad in "--quality 0" "--quality 101" "--quality x" "--max-edge 0" "--max-edge big"; do
  # shellcheck disable=SC2086  # flag and value
  shrink -n $bad a.jpg
  [[ "$rc" == 2 ]] || failed "$bad wasn't refused: rc $rc: $out"
done
rc=0
out="$(cd "$TMP/work" && "${clean[@]}" SHRINK_QUALITY=best /bin/bash "$REPO_DIR/bin/shrink" -n a.jpg 2>&1)" || rc=$?
[[ "$rc" == 2 && "$out" == *SHRINK_QUALITY* ]] || failed "SHRINK_QUALITY=best wasn't refused by name: rc $rc: $out"

echo "a missing magick or pngquant fails only the files needing it"
reset
input a.jpg
input b.png
input c.mov
without pngquant
rc=0
out="$(cd "$TMP/work" && "${clean[@]}" PATH="$TMP/without:/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" a.jpg b.png c.mov 2>&1)" || rc=$?
[[ "$rc" != 0 && "$out" == *"b.png: needs pngquant"*install.sh* ]] || failed "a missing pngquant wasn't named for b.png: rc $rc: $out"
[[ -f "$TMP/work/a.shrunk.jpg" && ! -e "$TMP/work/b.shrunk.png" ]] || failed "a missing pngquant stopped a.jpg or left b.png's copy: $out"
without magick
rm -f "$TMP"/work/*.shrunk.*
rc=0
out="$(cd "$TMP/work" && "${clean[@]}" PATH="$TMP/without:/usr/bin:/bin" /bin/bash "$REPO_DIR/bin/shrink" a.jpg c.mov 2>&1)" || rc=$?
[[ "$rc" != 0 && "$out" == *"a.jpg: needs magick"*install.sh* && -f "$TMP/work/c.shrunk.mp4" ]] ||
  failed "a missing magick wasn't named for a.jpg alone: rc $rc: $out"

echo "a missing ffmpeg is named, with install.sh"
reset
input a.mov
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
shrink --help image
for want in --max-edge SHRINK_MAX_EDGE 2560 --quality SHRINK_QUALITY 80 heic magick pngquant; do
  [[ "$out" == *"$want"* ]] || failed "--help image doesn't mention $want: $out"
done
help_image="$out"
shrink --help
[[ "$out" == *"$help_video"* ]] || failed "--help doesn't include the video settings: $out"
[[ "$out" == *"$help_image"* ]] || failed "--help doesn't include the image settings: $out"

if ((failures)); then
  echo "shrink: $failures failure(s)" >&2
  exit 1
fi
echo "shrink: ok"
