#!/bin/bash
# Builds a universal Tidepaper.app into ./build.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  also copy it to /Applications (quitting a running copy first)
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/Tidepaper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Tidepaper" "$APP/Contents/MacOS/Tidepaper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Ad-hoc signature: enough to run locally and to register as a login item.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Tidepaper || true
  rm -rf /Applications/Tidepaper.app
  cp -R "$APP" /Applications/
  echo "Installed /Applications/Tidepaper.app"
fi
