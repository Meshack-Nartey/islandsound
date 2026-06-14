#!/bin/bash
# Builds the IslandSound SPM executable and wraps it into a minimal
# IslandSound.app bundle (no Xcode project required).
#
# Usage: Scripts/build_app.sh [debug|release]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="IslandSound"
BUILD_CONFIG="${1:-release}"

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIG"

BIN_PATH="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
APP_BUNDLE="$ROOT_DIR/.build/$APP_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "Built $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
