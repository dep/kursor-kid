#!/bin/bash
# Builds, signs, and (optionally) notarizes "Kursor Kid.app".
#
#   scripts/build-app.sh            # build + sign only
#   scripts/build-app.sh --notarize # build + sign + notarize + staple + DMG
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Kursor Kid"
VERSION="1.0.0"
BUNDLE_ID="com.dannypeck.kursorkid"
IDENTITY="Developer ID Application: Danny Peck (299R8V27FZ)"
TEAM_ID="299R8V27FZ"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "▸ Building universal release binary"
swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/KursorKid"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KursorKid"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>KursorKid</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID.claude</string>
            <key>CFBundleURLSchemes</key><array><string>kursorkid</string></array>
        </dict>
    </array>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Danny Peck</string>
</dict>
</plist>
PLIST

echo "▸ Generating app icon"
ICON_SRC="/tmp/kursorkid-icon-1024.png"
".build/apple/Products/Release/KursorKid" --dump-icon "$ICON_SRC" > /dev/null
ICONSET="/tmp/KursorKid.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z $double $double "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing with hardened runtime"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

if [[ "${1:-}" != "--notarize" ]]; then
    echo "✓ Signed app at $APP (pass --notarize for distribution build)"
    exit 0
fi

echo "▸ Notarizing"
ZIP="$DIST/KursorKid-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

if xcrun notarytool history --keychain-profile notarytool > /dev/null 2>&1; then
    AUTH=(--keychain-profile notarytool)
else
    source .env
    AUTH=(--apple-id "$APPLE_EMAIL" --password "$APPLE_APP_PASSWORD" --team-id "$TEAM_ID")
fi
xcrun notarytool submit "$ZIP" "${AUTH[@]}" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"

# Refresh the zip so the shared archive contains the stapled app.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if command -v create-dmg > /dev/null; then
    echo "▸ Creating DMG"
    DMG_SRC="/tmp/kursorkid-dmg-src"
    rm -rf "$DMG_SRC" && mkdir -p "$DMG_SRC"
    cp -R "$APP" "$DMG_SRC/"
    rm -f "$DIST/KursorKid-$VERSION.dmg"
    create-dmg \
        --volname "$APP_NAME" \
        --volicon "$APP/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 --window-size 660 400 --icon-size 160 \
        --icon "$APP_NAME.app" 180 170 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 480 170 \
        "$DIST/KursorKid-$VERSION.dmg" "$DMG_SRC/"
else
    echo "(create-dmg not installed — skipping DMG, zip is ready)"
fi

echo "✓ Distribution build complete: $APP"
