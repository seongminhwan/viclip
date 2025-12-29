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
if [ -f "$BUILD_DIR/$APP_NAME" ]; then
    cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
else
    echo "❌ Error: Executable not found at $BUILD_DIR/$APP_NAME"
    echo "   Run 'swift build -c release' first"
    exit 1
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

# Perform Ad-Hoc signing with entitlements (fix for JSContext JIT crash)
echo "🔏 Signing app (ad-hoc with entitlements)..."
entitlements_path="Sources/Viclip/Resources/Viclip.entitlements"
if [ -f "$entitlements_path" ]; then
    codesign --force --deep --sign - --entitlements "$entitlements_path" "$APP_BUNDLE"
else
    echo "⚠️ Entitlements file not found, signing without them."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi


# Create Info.plist
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
</dict>
</plist>
EOF

# Copy entitlements if exists
if [ -f "Sources/Viclip/Resources/Viclip.entitlements" ]; then
    cp "Sources/Viclip/Resources/Viclip.entitlements" "$APP_BUNDLE/Contents/Resources/"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo "✅ App bundle created at: $APP_BUNDLE"
echo "   Contents:"
ls -la "$APP_BUNDLE/Contents/Resources/" | head -20
echo "   To run: open $APP_BUNDLE"
