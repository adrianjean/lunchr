#!/bin/zsh
# ./build.sh            build build/Lunchr.app
# ./build.sh install    build, copy to /Applications, (re)start
set -euo pipefail
cd "${0:a:h}"

swift build -c release
bin="$(swift build -c release --show-bin-path)/Lunchr"
app=build/Lunchr.app

rm -rf "$app"    # overwriting a running, signed binary gets it killed
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/Lunchr"
cp Info.plist "$app/Contents/Info.plist"

identity="$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID/ {print $2; exit}')"
codesign --force --options runtime --sign "${identity:--}" "$app"
echo "Built $app"

if [[ "${1:-}" == install ]]; then
  pkill -x Lunchr || true
  ditto "$app" /Applications/Lunchr.app
  open /Applications/Lunchr.app
  echo "Installed /Applications/Lunchr.app"
fi
