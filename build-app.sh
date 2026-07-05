#!/bin/bash
# Builds DynamicIsland.app from the SwiftPM package — no Xcode required.
# Usage: ./build-app.sh [--run]
set -euo pipefail

cd "$(dirname "$0")"

echo "▸ Release build…"
swift build -c release

APP="build/DynamicIsland.app"
BIN=".build/release/DynamicIsland"

echo "▸ Bundle oluşturuluyor: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DynamicIsland"
cp AppBundle/Info.plist "$APP/Contents/Info.plist"
cp AppBundle/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Ad-hoc imzalanıyor…"
codesign --force --sign - "$APP"

echo "✓ Hazır: $APP"
if [[ "${1:-}" == "--run" ]]; then
    echo "▸ Başlatılıyor…"
    open "$APP"
fi
