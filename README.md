# 05lali

macOS menu bar app prototype that draws a click-through fullscreen grid overlay above other windows.

## What it does

- Lives in the menu bar instead of the Dock.
- Toggles a fullscreen transparent overlay on and off.
- Draws grid lines in `#D2D5E1` at `50%` opacity.
- Uses adaptive line rendering so the guides stay visible by inverting underlying content.
- Starts with a `3 x 3` layout, which means two vertical and two horizontal guide lines.
- Keeps the overlay above normal app windows and allows mouse interaction to pass through.
- Rebuilds the overlay when display or Space configuration changes.
- Includes a `Settings...` window scaffold with a disabled `Start at login` checkbox.

## Project structure

- `Package.swift`: Swift Package manifest for a macOS executable target.
- `Sources/GridOverlay/main.swift`: Menu bar app, overlay windows, and grid drawing logic.
- `App/Info.plist`: App bundle metadata for the packaged `.app`.
- `scripts/build_app.sh`: Builds the executable and packages it into `05lali.app`.
- `scripts/build_dmg.sh`: Creates an install DMG with a custom Finder background.
- `Build/05lali.app`: Generated app bundle after packaging.

## Run in Xcode

1. Open `/Users/byeongsukim/05lali/Package.swift` in Xcode.
2. Choose the `GridOverlay` scheme.
3. Run the app.
4. Use the menu bar icon to turn the overlay on or off and change rows and columns.

## Build a real app bundle

1. Make sure the source icon exists at `/Users/byeongsukim/Downloads/AppIcon_05lali.png`.
2. Run `./scripts/build_app.sh`
3. Open `Build/05lali.app`

This packaging step creates:

- `Build/05lali.app`
- `Build/05lali.app/Contents/Resources/AppIcon.icns`
- A bundle named `05lali` with the custom app icon

## Build a DMG installer

1. Run `./scripts/build_app.sh`
2. Run `./scripts/build_dmg.sh`
3. Open `Build/05lali.dmg`

The DMG uses `/Users/byeongsukim/05lali/05lali_wallpaper.png` as the Finder background and lays out `05lali.app` beside the `Applications` shortcut.

## What you still need to do

- For personal use: run the build script and launch the generated app.
- For broader distribution: sign the app with your Apple Developer identity and notarize it.
- If you want a polished product next: wire up launch-at-login and replace the menu bar symbol with a custom template icon.

## Notes

- This version uses `NSWindow` with `ignoresMouseEvents = true`, so it should not block clicks.
- The overlay is configured for all Spaces and fullscreen apps, but some system-level surfaces can still appear above it.
- If you want a production Xcode project next, the natural follow-up is to convert this package into a native macOS app target with signing and archive support.
