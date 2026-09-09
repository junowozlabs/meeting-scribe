#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)}"
export BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Support/Info.plist)}"
export UNIVERSAL=1
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'VERSION must be x.y.z' >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] && ((BUILD_NUMBER >= 1000)) || { echo 'BUILD_NUMBER must be at least 1000 for this app identity' >&2; exit 1; }
script/package-app.sh
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto dist/MeetingScribe.app "$STAGING/MeetingScribe.app"
ln -s /Applications "$STAGING/Applications"
cp Support/INSTALL.txt "$STAGING/LEIA-ME.txt"
mkdir -p dist/release
DMG="dist/release/MeetingScribe.dmg"
rm -f "$DMG" dist/release/appcast.xml
hdiutil create -volname 'Meeting Scribe' -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
GENERATE=.build/artifacts/sparkle/Sparkle/bin/generate_appcast
URL="https://github.com/junowozlabs/meeting-scribe/releases/download/v$VERSION/"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE" --ed-key-file - --minimum-update-version 1000 --download-url-prefix "$URL" dist/release
else
  "$GENERATE" --account com.junowozlabs.MeetingScribe --minimum-update-version 1000 --download-url-prefix "$URL" dist/release
fi
(cd dist/release && shasum -a 256 MeetingScribe.dmg > SHA256SUMS)
