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

# Layered icon for macOS 26+, .icns for older. actool comes with Xcode, not the command line tools.
mkdir -p "$app/Contents/Resources"
if xcrun --find actool >/dev/null 2>&1; then
  xcrun actool Icon/Lunchr.icon --compile "$app/Contents/Resources" --app-icon Lunchr \
    --platform macosx --target-device mac --minimum-deployment-target 14.0 \
    --output-partial-info-plist .build/icon.plist --errors --warnings >/dev/null
else
  echo "No Xcode: building without the app icon"
fi

identity="$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID/ {print $2; exit}')"
codesign --force --options runtime --sign "${identity:--}" "$app"
echo "Built $app"

if [[ "${1:-}" == install ]]; then
  pkill -x Lunchr || true
  ditto "$app" /Applications/Lunchr.app
  open /Applications/Lunchr.app
  echo "Installed /Applications/Lunchr.app"
fi
