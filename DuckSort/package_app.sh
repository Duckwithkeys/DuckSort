#!/bin/bash
set -e

# Ensure we run from the project root
cd "$(dirname "$0")"

echo "=== Building DuckSort in Release mode ==="
# Use the beta Xcode if it exists and DEVELOPER_DIR is not already set
if [ -z "$DEVELOPER_DIR" ] && [ -d "/Users/oliver/Downloads/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Users/oliver/Downloads/Xcode-beta.app/Contents/Developer"
fi

xcodebuild -scheme DuckSort -destination 'platform=macOS' -configuration Release SYMROOT=build OBJROOT=build/intermediates CODE_SIGNING_ALLOWED=NO build

echo "=== Copying App Bundle ==="
APP_DIR="DuckSort.app"
rm -rf "$APP_DIR"
cp -R build/Release/DuckSort.app ./

# Ensure the AppIcon.icns and dynamic variants are placed inside Resources
mkdir -p "$APP_DIR/Contents/Resources/AppIcons"
cp DuckSort/Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
cp DuckSort/Resources/AppIcon-Light.icns "$APP_DIR/Contents/Resources/AppIcon-Light.icns"
cp DuckSort/Resources/AppIcon-Dark.icns "$APP_DIR/Contents/Resources/AppIcon-Dark.icns"
cp DuckSort/Resources/AppIcons/*.png "$APP_DIR/Contents/Resources/AppIcons/"
cp DuckSort/Resources/AppIcons/*.png "$APP_DIR/Contents/Resources/"

echo "=== Codesigning App Bundle ==="
find build/Release -name "._*" -exec rm -f {} + || true
find "$APP_DIR" -name "._*" -exec rm -f {} + || true
xattr -cr build/Release || true
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
touch "$APP_DIR"

echo "=== Package Complete: DuckSort.app ==="

