#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
OUTPUT_DIR="$PROJECT_DIR/../../outputs"
APP_DIR="$OUTPUT_DIR/AirDropAutoAccept.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

swift build -c release --package-path "$PROJECT_DIR" --triple arm64-apple-macosx13.0
swift build -c release --package-path "$PROJECT_DIR" --triple x86_64-apple-macosx13.0
lipo -create \
    "$PROJECT_DIR/.build/arm64-apple-macosx/release/AirDropAutoAccept" \
    "$PROJECT_DIR/.build/x86_64-apple-macosx/release/AirDropAutoAccept" \
    -output "$MACOS_DIR/AirDropAutoAccept"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Assets/AirDropAutoAccept.icns" "$RESOURCES_DIR/AirDropAutoAccept.icns"

chmod +x "$MACOS_DIR/AirDropAutoAccept"

# A stable Developer ID signature keeps the Accessibility grant attached to
# this app across rebuilds. Never silently fall back to an ad-hoc signature:
# that would recreate the Gatekeeper warning users see with downloaded builds.
SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application:/{print $2; exit}')"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Developer ID Application certificate not found; refusing to create an unsigned distribution build." >&2
    exit 1
fi
codesign --force --deep --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built: $APP_DIR"
