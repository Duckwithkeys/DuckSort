#!/bin/bash
set -e

# Ensure we run from the project root
cd "$(dirname "$0")"

APP_NAME="DuckSort.app"
DMG_NAME="DuckSort.dmg"
WORKSPACE="dmg_workspace"

if [ ! -d "$APP_NAME" ]; then
    echo "Error: $APP_NAME not found! Run ./package_app.sh first."
    exit 1
fi

echo "=== Creating DMG Workspace ==="
rm -rf "$WORKSPACE"
mkdir -p "$WORKSPACE"

echo "=== Copying App Bundle ==="
cp -R "$APP_NAME" "$WORKSPACE/"

echo "=== Creating Applications Symlink ==="
ln -s /Applications "$WORKSPACE/Applications"

echo "=== Setting Volume Icon ==="
if [ -f "$WORKSPACE/$APP_NAME/Contents/Resources/AppIcon.icns" ]; then
    cp "$WORKSPACE/$APP_NAME/Contents/Resources/AppIcon.icns" "$WORKSPACE/.VolumeIcon.icns"
    SetFile -c icnC "$WORKSPACE/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$WORKSPACE" 2>/dev/null || true
fi

echo "=== Building Compressed DMG ==="
rm -f "$DMG_NAME"
hdiutil create -volname "DuckSort" -srcfolder "$WORKSPACE" -ov -format UDZO "$DMG_NAME"

echo "=== Cleaning Up ==="
rm -rf "$WORKSPACE"

echo "=== DMG Build Complete: $DMG_NAME ==="
