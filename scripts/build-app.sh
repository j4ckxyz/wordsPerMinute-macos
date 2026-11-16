#!/bin/zsh
# Builds WPM.app (release, arm64 + x86_64 when available) into macos/build/.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG" --arch arm64 --arch x86_64 2>/dev/null || swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path 2>/dev/null || swift build -c "$CONFIG" --show-bin-path)"
[[ -x "$BIN/WPMBar" ]] || BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/WPM.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/WPMBar" "$APP/Contents/MacOS/WPMBar"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Ad-hoc signature so TCC (Input Monitoring) and SMAppService can identify the app.
# Set SIGN_IDENTITY="Developer ID Application: …" to sign for real.
codesign --force --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $(pwd)/$APP"
