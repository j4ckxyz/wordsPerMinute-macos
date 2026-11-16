#!/usr/bin/env bash
# Installs (or uninstalls) WPM, the menu bar words-per-minute counter.
#
#   install.sh                 install the latest release
#   install.sh --version v0.1.0
#   install.sh --uninstall     remove the app (keeps your stats)
#   install.sh --purge         remove the app, its stats, settings and permission entry
#
# Downloads with the GitHub CLI (`gh`) when it's installed and signed in, which also
# works while the repo is private. Otherwise uses plain curl, which needs the repo
# to be public.
set -euo pipefail

REPO="${WPM_REPO:-j4ckxyz/wordsPerMinute-macos}"
APP_NAME="WPM.app"
BUNDLE_ID="local.wpmbar.WPMBar"
PROCESS_NAME="WPMBar"

TAG=""
MODE="install"
while [ $# -gt 0 ]; do
  case "$1" in
    --version) TAG="${2:?--version needs a tag, e.g. v0.1.0}"; shift 2 ;;
    --uninstall) MODE="uninstall"; shift ;;
    --purge) MODE="purge"; shift ;;
    -h|--help) sed -n '2,11p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "WPM is a macOS app."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 15 ] || die "WPM needs macOS 15 or later (this Mac has $(sw_vers -productVersion))."

quit_running_app() {
  if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
    say "Quitting the running copy of WPM"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    sleep 1
    pkill -x "$PROCESS_NAME" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------- uninstall
if [ "$MODE" != "install" ]; then
  quit_running_app
  removed=0
  for dir in /Applications "$HOME/Applications"; do
    if [ -d "$dir/$APP_NAME" ]; then
      rm -rf "${dir:?}/$APP_NAME" && say "Removed $dir/$APP_NAME" && removed=1
    fi
  done
  [ "$removed" = 1 ] || say "WPM.app wasn't installed in /Applications or ~/Applications"
  if [ "$MODE" = "purge" ]; then
    rm -rf "$HOME/Library/Application Support/WPMBar"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
    say "Removed stats, settings and the Input Monitoring entry"
  fi
  exit 0
fi

# ---------------------------------------------------------------- download
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

downloaded_with=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  say "Downloading ${TAG:-the latest release} with gh"
  # shellcheck disable=SC2086
  if gh release download ${TAG:+"$TAG"} --repo "$REPO" --dir "$TMP" \
       --pattern 'WPM-*.zip' --pattern 'SHA256SUMS.txt' 2>"$TMP/gh.err"; then
    downloaded_with="gh"
  else
    echo "    gh couldn't download it ($(head -1 "$TMP/gh.err")); trying curl" >&2
  fi
fi

if [ -z "$downloaded_with" ]; then
  if [ -z "$TAG" ]; then
    say "Finding the latest release"
    latest_url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null || true)"
    case "$latest_url" in
      */releases/tag/*) TAG="${latest_url##*/tag/}" ;;
      *) die "Couldn't reach https://github.com/$REPO/releases.
       If the repo is still private, install the GitHub CLI and sign in first:
         brew install gh && gh auth login" ;;
    esac
  fi
  version="${TAG#v}"
  say "Downloading WPM $version with curl"
  base="https://github.com/$REPO/releases/download/$TAG"
  curl -fsSL -o "$TMP/WPM-$version.zip" "$base/WPM-$version.zip" || die "Download failed: $base/WPM-$version.zip"
  curl -fsSL -o "$TMP/SHA256SUMS.txt" "$base/SHA256SUMS.txt" || true
  downloaded_with="curl"
fi

ZIP="$(ls "$TMP"/WPM-*.zip 2>/dev/null | head -1)"
[ -n "$ZIP" ] || die "The release has no WPM-*.zip asset."

# ---------------------------------------------------------------- verify
if [ -f "$TMP/SHA256SUMS.txt" ]; then
  expected="$(grep " $(basename "$ZIP")\$" "$TMP/SHA256SUMS.txt" | awk '{print $1}')"
  actual="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
  [ -n "$expected" ] || die "SHA256SUMS.txt has no entry for $(basename "$ZIP")"
  [ "$expected" = "$actual" ] || die "Checksum mismatch for $(basename "$ZIP")"
  say "Checksum OK"
else
  echo "    (no SHA256SUMS.txt in the release; skipping checksum check)" >&2
fi

# ---------------------------------------------------------------- install
if [ -w /Applications ]; then
  DEST="/Applications"
else
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

quit_running_app
ditto -x -k "$ZIP" "$TMP/unpacked"
[ -d "$TMP/unpacked/$APP_NAME" ] || die "The zip doesn't contain $APP_NAME"
rm -rf "${DEST:?}/$APP_NAME"
ditto "$TMP/unpacked/$APP_NAME" "$DEST/$APP_NAME"
# The app is ad-hoc signed, not notarised: clear quarantine so Gatekeeper doesn't block it.
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true
say "Installed $DEST/$APP_NAME ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/$APP_NAME/Contents/Info.plist"), via $downloaded_with)"

open "$DEST/$APP_NAME"
say "WPM is running in your menu bar. On first launch, allow Input Monitoring when asked."
echo "    To uninstall later: rerun this script with --uninstall (or --purge to remove stats too)."
