#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release --product KeyboardLock
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PWD/dist/Keyboard Lock.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$BIN_DIR/KeyboardLock" "$APP_DIR/Contents/MacOS/KeyboardLock"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
chmod 755 "$APP_DIR/Contents/MacOS/KeyboardLock"

plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - --identifier com.personal.keyboard-lock "$APP_DIR"

echo
echo "Built: $APP_DIR"
echo "Copy it to /Applications before granting Accessibility permission."
