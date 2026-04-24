#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="05lali"
APP_BUNDLE="$ROOT_DIR/Build/$APP_NAME.app"
DMG_BACKGROUND="$ROOT_DIR/05lali_wallpaper.png"
STAGING_DIR="$ROOT_DIR/Build/dmg-staging"
FINAL_DMG="$ROOT_DIR/Build/$APP_NAME.dmg"
VOLUME_NAME="$APP_NAME"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing app bundle: $APP_BUNDLE" >&2
  echo "Run ./scripts/build_app.sh first." >&2
  exit 1
fi

if [[ ! -f "$DMG_BACKGROUND" ]]; then
  echo "Missing DMG background: $DMG_BACKGROUND" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "create-dmg not found. Install with: brew install create-dmg" >&2
  exit 1
fi

rm -rf "$STAGING_DIR" "$FINAL_DMG"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

echo "Creating DMG with create-dmg..."
create-dmg \
  --volname "$VOLUME_NAME" \
  --background "$DMG_BACKGROUND" \
  --window-pos 129 129 \
  --window-size 640 480 \
  --icon-size 128 \
  --icon "$APP_NAME.app" 195 240 \
  --app-drop-link 445 240 \
  --hide-extension "$APP_NAME.app" \
  --no-internet-enable \
  "$FINAL_DMG" \
  "$STAGING_DIR"

rm -rf "$STAGING_DIR"

echo "DMG created at:"
echo "  $FINAL_DMG"
