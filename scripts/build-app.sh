#!/bin/zsh
# Builds build/WPM.app: release, universal (arm64 + x86_64) when possible,
# otherwise the native architecture. Ad-hoc signed.
#   SIGN_IDENTITY="Developer ID Application: …"  sign with a real identity instead
#   ARCHS="arm64"                                 restrict architectures
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
ARCHS=(${=ARCHS:-arm64 x86_64})

# Build each architecture separately and merge with lipo. (SwiftPM's own
# multi-arch mode needs Xcode's xcbuild; per-triple builds work with just the CLT.)
slices=()
for arch in $ARCHS; do
  triple="$arch-apple-macosx15.0"
  echo "==> Building $arch"
  if swift build -c release --triple "$triple" >/dev/null; then
    slices+=("$(swift build -c release --triple "$triple" --show-bin-path)/WPMBar")
  else
    echo "    (skipping $arch: build failed)" >&2
  fi
done
(( ${#slices} > 0 )) || { echo "No architecture built" >&2; exit 1; }

APP="build/WPM.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/WPMBar"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate with: swift scripts/make-icon.swift Support/AppIcon.icns
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
                        -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

# Ad-hoc signature so TCC (Input Monitoring) and SMAppService can identify the app.
codesign --force --options runtime --timestamp=none --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "Built $(pwd)/$APP  v$VERSION ($BUILD_NUMBER)  [$(lipo -archs "$APP/Contents/MacOS/WPMBar")]"
