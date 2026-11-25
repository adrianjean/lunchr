#!/bin/zsh
# Demo/media.sh                  film the staged demo and cut docs/media (takes the screen and keyboard for 45 s; Esc stops)
# Demo/media.sh picture.jpg      the same, over your own background (fills 16:10, cropped to fit)
# Demo/media.sh cut              cut again from the last take
# LUNCHR_WINDOWS=0 in front      leave out the two dummy windows
# OUT=folder in front            save there instead of docs/media
# Needs ffmpeg. Blank settings and stock macOS apps: nothing of yours is in it but the picture you pass.
set -euo pipefail
out="${OUT:-docs/media}"
[[ -n "${OUT:-}" ]] && out="${OUT:a}"
if [[ -n "${1:-}" && "$1" != cut ]]; then
  export LUNCHR_BACKGROUND="${1:a}"
  sips -g pixelWidth "$LUNCHR_BACKGROUND" 2>/dev/null | grep -q 'pixelWidth: [0-9]' || { echo "Not a picture: $1"; exit 1 }
fi
cd "${0:a:h}/.."
raw=.build/demo
mkdir -p $out

if [[ "${1:-}" != cut ]]; then
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

for theme in graphite paper ember clear midnight meadow console; do
  ff -i $raw/$theme.png -vf "crop=1640:1000:460:180,scale=1100:-1:flags=lanczos" $clean $out/$theme.png
done
for shot in naked settings; do ff -i $raw/$shot.png -vf "scale=1600:-1:flags=lanczos" $clean $out/$shot.png; done
ls -lh $out
