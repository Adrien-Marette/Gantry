#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${1:-release}"
swift build -c "$CONFIGURATION"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BIN_PATH="$BIN_DIR/Gantry"
HELPER_BIN="$BIN_DIR/Gantry-plugins"
APP_DIR="$ROOT/build/Gantry.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

mkdir -p "$ROOT/build"
if [[ -d "$APP_DIR" ]]; then
    /bin/rm -rf "$APP_DIR"
fi
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/Gantry"
chmod +x "$MACOS_DIR/Gantry"
cp "$HELPER_BIN" "$MACOS_DIR/Gantry-plugins"
chmod +x "$MACOS_DIR/Gantry-plugins"
/usr/bin/codesign --force --sign - "$MACOS_DIR/Gantry-plugins" >/dev/null
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

ICONSET="$ROOT/build/AppIcon.iconset"
/bin/rm -rf "$ICONSET"
swift "$ROOT/Scripts/generate-icon.swift" "$ICONSET"
iconutil --convert icns "$ICONSET" --output "$RESOURCES_DIR/AppIcon.icns"

/usr/bin/codesign --force --sign - "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
echo "Open it with: open \"$APP_DIR\""
