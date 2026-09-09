#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CONFIGURATION="${CONFIGURATION:-release}"
APP_BUNDLE="$ROOT_DIR/dist/MeetingScribe.app"
BUILD_ARGS=(-c "$CONFIGURATION")
if [[ "${UNIVERSAL:-0}" == 1 ]]; then BUILD_ARGS+=(--arch arm64 --arch x86_64); fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
# Delete only the generated bundle, never user documents.
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
cp "$BIN_DIR/MeetingScribe" "$APP_BUNDLE/Contents/MacOS/MeetingScribe"
cp Support/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
SPARKLE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
fi
FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
# Re-sign nested tools explicitly. --deep signing overwrites helper entitlements.
for ITEM in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  codesign --force --sign - --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/$ITEM"
done
codesign --force --sign - "$FRAMEWORK"
codesign --force --sign - --entitlements Support/MeetingScribe.entitlements "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
printf 'App: %s\n' "$APP_BUNDLE"
