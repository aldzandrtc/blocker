#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Blocker"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
RELEASE_BIN="$BUILD_DIR/release/$APP_NAME"

# --- Build release binary ---
echo "=== Building release binary ==="
swift build -c release --package-path "$PROJECT_DIR"

# --- Clean previous app bundle ---
rm -rf "$APP_BUNDLE"

# --- Create app bundle structure ---
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# --- Copy binary ---
cp "$RELEASE_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# --- Copy Info.plist ---
if [ -f "$PROJECT_DIR/Resources/Info.plist" ]; then
    cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
else
    # Fallback: generate minimal Info.plist
    cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Blocker</string>
    <key>CFBundleName</key>
    <string>Blocker</string>
    <key>CFBundleIdentifier</key>
    <string>com.blocker.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
    echo "Generated default Info.plist"
fi

# --- Generate icon ---
"$SCRIPT_DIR/generate-icon.swift" "$APP_BUNDLE/Contents/Resources"
rm -rf "$APP_BUNDLE/Contents/Resources/AppIcon.iconset"

# --- Copy Chrome extension to Desktop (so it's selectable in Finder) ---
CHROME_EXT_SRC="$PROJECT_DIR/Blocker/ChromeExt"
DESKTOP_EXT="$HOME/Desktop/BlockerChromeExt"
if [ -d "$CHROME_EXT_SRC" ]; then
    rm -rf "$DESKTOP_EXT"
    cp -R "$CHROME_EXT_SRC/" "$DESKTOP_EXT/"
    echo "Chrome extension: $DESKTOP_EXT"

    # Also copy into app bundle
    mkdir -p "$APP_BUNDLE/Contents/Resources/ChromeExt"
    cp -R "$CHROME_EXT_SRC/" "$APP_BUNDLE/Contents/Resources/ChromeExt/"
fi

# --- Strip extended attributes ---
# Prevent Gatekeeper quarantine issues on double-click
xattr -cr "$APP_BUNDLE" 2>/dev/null || true

# --- Create PkgInfo (required for some macOS versions) ---
echo -n 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# --- Re-sign the app bundle (ad-hoc) ---
# SPM build produces a linker-signed binary that expects resources.
# After adding Info.plist + icon + ChromeExt we must re-sign so the
# signature covers all resources.
echo "=== Signing ==="
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1
echo "Ad-hoc signature applied"

# --- Install to /Applications ---
INSTALL_APP="/Applications/$APP_NAME.app"
rm -rf "$INSTALL_APP"
cp -R "$APP_BUNDLE" "$INSTALL_APP"
xattr -cr "$INSTALL_APP" 2>/dev/null || true

echo ""
echo "=== Installed ==="
echo "  App:      $INSTALL_APP"
echo "  Chrome ext: $DESKTOP_EXT"
echo ""
echo "To run: open \"$INSTALL_APP\""
echo "First launch: right-click → Open (Gatekeeper workaround, one-time)"
echo ""
echo "Chrome: chrome://extensions → Load unpacked → select BlockerChromeExt on Desktop"
