#!/bin/zsh
# Demo/media.sh [picture.jpg] [--no-windows] [--out folder]
#   Films the staged demo and cuts docs/media. Takes the screen and keyboard for 45 s; Esc stops it.
#   picture.jpg     your own background (fills 16:10, cropped to fit)
#   --no-windows    leave out the dark and light windows
#   --out folder    save there instead of docs/media
# Demo/media.sh cut [--out folder]    cut again from the last take
# Needs ffmpeg. Blank settings and stock macOS apps: nothing of yours is in it but the picture you pass.
set -euo pipefail
out=docs/media cut=0
while (( $# )); do
  case "$1" in
    --no-windows) export LUNCHR_WINDOWS=0 ;;
    --out) [[ -n "${2:-}" ]] || { echo "--out needs a folder"; exit 1 }; out="${2:a}"; shift ;;
    cut) cut=1 ;;
    -*) echo "Unknown option: $1"; exit 1 ;;
    *)
      export LUNCHR_BACKGROUND="${1:a}"
      sips -g pixelWidth "$LUNCHR_BACKGROUND" 2>/dev/null | grep -q 'pixelWidth: [0-9]' \
        || { echo "Not a picture: $1"; exit 1 } ;;
  esac
  shift
done
cd "${0:a:h}/.."
raw=.build/demo
mkdir -p $out

if (( ! cut )); then
  rm -rf $raw
  mkdir -p $raw/home
  cp Demo/config.json $raw/home/config.json
  swift build
  LUNCHR_HOME=$PWD/$raw/home LUNCHR_ROOTS=/System/Applications:/System/Cryptexes/App/System/Applications \
    LUNCHR_DEMO=$PWD/$raw .build/debug/Lunchr
fi

clean=(-map_metadata -1 -fflags +bitexact -flags:v +bitexact)
ff() { ffmpeg -loglevel error -y "$@" }

# Every clip starts and ends on the same empty desktop, so plain cuts don't show.
inputs=() graph="" n=0
for theme in graphite paper ember clear naked; do
  inputs+=(-ss 0.3 -i $raw/$theme.mov)
  graph+="[$n]fps=60,scale=1920:1200:flags=lanczos:out_color_matrix=bt709,setsar=1[v$n];"
  n=$((n + 1))
done
for i in {0..$((n - 1))}; do graph+="[v$i]"; done
graph+="concat=n=$n:v=1:a=0,format=yuv420p[v]"
ff $inputs -filter_complex "$graph" -map "[v]" -c:v libx264 -crf 17 -preset slow \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -movflags +faststart $clean $out/lunchr.mp4

gif() { ff -ss $1 -i $2 -vf "fps=30,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" $clean $3 }
gif 0.3 $raw/naked.mov $out/naked.gif
gif 0 $out/lunchr.mp4 $out/lunchr.gif

# Same framing as the video.
for shot in graphite paper ember clear midnight meadow console naked settings; do
  ff -i $raw/$shot.png -vf "scale=1920:-1:flags=lanczos" $clean $out/$shot.png
done
ls -lh $out
