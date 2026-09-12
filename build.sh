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

# Prefer a stable Developer ID requirement when one is available. TCC's
# Accessibility grant is otherwise tied to each ad-hoc build's code hash and
# gets invalidated whenever the app is rebuilt.
SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application:/{print $2; exit}')"
if [[ -n "$SIGNING_IDENTITY" ]]; then
    if ! codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR" >/dev/null 2>&1; then
        echo "Developer ID signing unavailable; using an ad-hoc local signature." >&2
        codesign --force --deep --sign - "$APP_DIR" >/dev/null
    fi
else
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi
echo "Built: $APP_DIR"
