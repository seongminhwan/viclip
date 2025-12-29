#!/bin/bash
set -e

# Viclip App Bundle Packaging Script
# Creates a macOS .app bundle from Swift build output

APP_NAME="Viclip"
BUNDLE_ID="com.viclip.clipboard"
VERSION="0.01"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

echo "📦 Packaging $APP_NAME..."

# Clean and create dist directory
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
# Clean build directory to ensure flags take effect
rm -rf "$BUILD_DIR"
rm -rf .build/arm64-apple-macosx/release

# Build with privacy flags (remap absolute paths)
echo "🔨 Building Release (Privacy Mode)..."
swift build -c release \
    -Xswiftc -debug-prefix-map -Xswiftc $(pwd)=. \
    -Xswiftc -debug-prefix-map -Xswiftc $(pwd)/.build/checkouts=.build/checkouts

# Copy executable
if [ -f "$BUILD_DIR/$APP_NAME" ]; then
    cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
    
    # Strip local symbols to remove remaining paths
    echo "🧹 Stripping symbols for privacy..."
    strip -r -S "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
else
    echo "❌ Error: Executable not found at $BUILD_DIR/$APP_NAME"
    exit 1
fi

# Copy app icon
echo "🎨 Copying app icon..."
if [ -f "Sources/Viclip/Resources/AppIcon.icns" ]; then
    cp "Sources/Viclip/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "   ✅ AppIcon.icns copied"
else
    echo "   ⚠️ AppIcon.icns not found"
fi

# Copy resource bundles (Highlightr, KeyboardShortcuts, etc.)
echo "📁 Copying resource bundles..."
for bundle in "$BUILD_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        bundle_name=$(basename "$bundle")
        echo "   Copying $bundle_name"
        cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"

        # Ensure bundle has Info.plist (fix for Bundle(path:) returning nil)
        bundle_plist="$APP_BUNDLE/Contents/Resources/$bundle_name/Info.plist"
        if [ ! -f "$bundle_plist" ]; then
            echo "   📝 Generating Info.plist for $bundle_name"
            defaults write "$bundle_plist" CFBundleIdentifier "com.viclip.$bundle_name"
            defaults write "$bundle_plist" CFBundleName "$bundle_name"
            defaults write "$bundle_plist" CFBundlePackageType "BNDL"
        fi
    fi
done

# Create Info.plist BEFORE signing
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024 Viclip. MIT License.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Viclip needs to control System Events to paste clipboard content into other applications.</string>
</dict>
</plist>
EOF

# Copy entitlements to Resources BEFORE signing
if [ -f "Sources/Viclip/Resources/Viclip.entitlements" ]; then
    cp "Sources/Viclip/Resources/Viclip.entitlements" "$APP_BUNDLE/Contents/Resources/"
fi

# Create PkgInfo BEFORE signing
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# IMPORTANT: Signing MUST be the LAST step after all files are in place
# Any modification to the bundle after signing will invalidate the signature
echo "🔏 Signing app (ad-hoc with entitlements for JSContext JIT support)..."
entitlements_path="Sources/Viclip/Resources/Viclip.entitlements"
if [ -f "$entitlements_path" ]; then
    codesign --force --deep --sign - --entitlements "$entitlements_path" "$APP_BUNDLE"
    echo "   ✅ Signed with entitlements (JIT enabled)"
else
    echo "⚠️ Entitlements file not found, signing without them."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

# Verify signature
echo "🔍 Verifying signature..."
if codesign --verify --verbose=1 "$APP_BUNDLE" 2>&1; then
    echo "   ✅ Signature valid"
else
    echo "   ⚠️ Signature verification failed"
fi

echo "✅ App bundle created at: $APP_BUNDLE"
echo "   Contents:"
ls -la "$APP_BUNDLE/Contents/Resources/" | head -20

# Create DMG
echo "💿 Creating DMG..."
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TMP_DMG_DIR="$DIST_DIR/dmg_tmp"

# Clean up previous DMG and temp dir
rm -f "$DMG_PATH"
rm -rf "$TMP_DMG_DIR"

# Create temp dir for DMG content
mkdir -p "$TMP_DMG_DIR"

# Copy App to temp dir
cp -R "$APP_BUNDLE" "$TMP_DMG_DIR/"

# Create /Applications symlink
ln -s /Applications "$TMP_DMG_DIR/Applications"

# Create DMG using hdiutil
hdiutil create -volname "$APP_NAME" -srcfolder "$TMP_DMG_DIR" -ov -format UDZO "$DMG_PATH"

# Clean up temp dir
rm -rf "$TMP_DMG_DIR"

echo "✅ DMG created at: $DMG_PATH"
echo "   To open: open $DMG_PATH"
