#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="05lali"
EXECUTABLE_NAME="GridOverlay"
SOURCE_ICON="$ROOT_DIR/AppIcon_05lali.png"
MENU_BAR_ICON="$ROOT_DIR/menubarIcon_05lali_2.png"
SETTINGS_PREVIEW_IMAGE="$ROOT_DIR/SettingsPreview.png"
BUILD_DIR="$ROOT_DIR/Build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Missing icon source: $SOURCE_ICON" >&2
  exit 1
fi

if [[ ! -f "$MENU_BAR_ICON" ]]; then
  echo "Missing menu bar icon source: $MENU_BAR_ICON" >&2
  exit 1
fi

if [[ ! -f "$SETTINGS_PREVIEW_IMAGE" ]]; then
  echo "Missing settings preview image: $SETTINGS_PREVIEW_IMAGE" >&2
  exit 1
fi

echo "Building Swift executable..."
cd "$ROOT_DIR"
swift build

echo "Preparing app bundle..."
rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

cp "$ROOT_DIR/.build/debug/$EXECUTABLE_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$MENU_BAR_ICON" "$RESOURCES_DIR/MenuBarIcon.png"
cp "$SETTINGS_PREVIEW_IMAGE" "$RESOURCES_DIR/SettingsPreview.png"

echo "Generating icns from PNG..."
sips -z 16 16   "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32   "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32   "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64   "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$SOURCE_ICON" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"

echo "App bundle created at:"
echo "  $APP_DIR"
