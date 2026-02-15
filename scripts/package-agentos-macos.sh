#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/AgentOS"
APP_NAME="AgentOS"
BUILD_BINARY="$PACKAGE_DIR/.build/release/$APP_NAME"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_PATH="$DIST_DIR/${APP_NAME}-macOS.zip"
DMG_PATH="$DIST_DIR/${APP_NAME}-macOS.dmg"
DMG_ROOT="$DIST_DIR/.dmg-root"

mkdir -p "$DIST_DIR"

echo "Building release binary..."
swift build -c release --package-path "$PACKAGE_DIR"

if [[ ! -f "$BUILD_BINARY" ]]; then
  echo "Error: release binary not found at $BUILD_BINARY" >&2
  exit 1
fi

echo "Creating .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_BINARY" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>AgentOS</string>
  <key>CFBundleDisplayName</key>
  <string>AgentOS</string>
  <key>CFBundleIdentifier</key>
  <string>com.nexusprotocol.agentos</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleExecutable</key>
  <string>AgentOS</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Signing .app with ad-hoc signature..."
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Creating .zip archive..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Creating .dmg installer..."
rm -f "$DMG_PATH"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
cp -R "$APP_DIR" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "AgentOS Installer" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_ROOT"

echo "Done."
echo "App: $APP_DIR"
echo "ZIP: $ZIP_PATH"
echo "DMG: $DMG_PATH"
