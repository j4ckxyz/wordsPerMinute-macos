#!/bin/zsh
# Packages a release into dist/:
#   WPM-<version>.dmg   drag-to-Applications disk image
#   WPM-<version>.zip   the app, zipped with ditto (used by install.sh)
#   SHA256SUMS.txt      checksums for both
# Ad-hoc signed only (no Developer ID), so it isn't notarised.
# Uses create-dmg if it's already installed, otherwise plain hdiutil.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
NAME="WPM-$VERSION"
VOLNAME="WPM $VERSION"
DIST="dist"
APP="build/WPM.app"

[[ "${SKIP_BUILD:-0}" == 1 && -d "$APP" ]] || ./scripts/build-app.sh

rm -rf "$DIST"
mkdir -p "$DIST"
DMG="$DIST/$NAME.dmg"
WORK="$(mktemp -d)"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
trap 'rm -rf "$WORK"' EXIT

echo "==> Building $DMG"
if command -v create-dmg >/dev/null; then
  create-dmg --volname "$VOLNAME" --window-size 540 360 --icon-size 112 \
    --icon "WPM.app" 140 170 --app-drop-link 400 170 --hide-extension "WPM.app" \
    --no-internet-enable "$DMG" "$APP"
else
  ditto "$APP" "$STAGE/WPM.app"
  ln -s /Applications "$STAGE/Applications"
  RW="$WORK/rw.dmg"
  hdiutil create -fs HFS+ -volname "$VOLNAME" -srcfolder "$STAGE" -format UDRW -ov "$RW"
  MOUNT="$(hdiutil attach -nobrowse -noautoopen -readwrite "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')"
  # Best effort: lay out the Finder window (needs a logged-in, unlocked GUI session
  # and Finder automation permission; skipped quietly otherwise).
  if osascript >/dev/null 2>&1 <<OSA
with timeout of 20 seconds
  tell application "Finder"
    set d to disk "$VOLNAME"
    open d
    set w to container window of d
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set bounds of w to {200, 120, 740, 480}
    set o to icon view options of w
    set arrangement of o to not arranged
    set icon size of o to 112
    set position of item "WPM.app" of d to {140, 170}
    set position of item "Applications" of d to {400, 170}
    update d without registering applications
    close w
  end tell
end timeout
OSA
  then echo "    Finder layout applied"; else echo "    (Finder layout skipped: no GUI session)"; fi
  sync
  hdiutil detach -quiet "$MOUNT" || hdiutil detach -quiet -force "$MOUNT"
  hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
fi
codesign --force --sign - "$DMG"

echo "==> Zipping app"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"

(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
echo "==> Done"
ls -lh "$DIST"
cat "$DIST/SHA256SUMS.txt"
