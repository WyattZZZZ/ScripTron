#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT_DIR/macos/ScripTronNative"
DIST_DIR="$APP_DIR/dist"
BUNDLE_NAME="ScripTron.app"
BUNDLE_DIR="$DIST_DIR/$BUNDLE_NAME"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

export PATH="/opt/homebrew/opt/rustup/bin:$PATH"

cd "$ROOT_DIR"
cargo build -p scriptron-ffi

cd "$APP_DIR"
swift build

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR"

cp "$APP_DIR/.build/debug/ScripTronNative" "$MACOS_DIR/ScripTron"
cp "$ROOT_DIR/target/debug/libscriptron_ffi.dylib" "$FRAMEWORKS_DIR/libscriptron_ffi.dylib"
chmod +x "$MACOS_DIR/ScripTron"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ScripTron</string>
    <key>CFBundleIdentifier</key>
    <string>com.scriptron.native</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ScripTron</string>
    <key>CFBundleDisplayName</key>
    <string>ScripTron</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

cat > "$CONTENTS_DIR/PkgInfo" <<'PKGINFO'
APPL????
PKGINFO

install_name_tool \
    -change "$ROOT_DIR/target/debug/deps/libscriptron_ffi.dylib" \
    "@executable_path/../Frameworks/libscriptron_ffi.dylib" \
    "$MACOS_DIR/ScripTron"

install_name_tool \
    -change "$ROOT_DIR/target/debug/libscriptron_ffi.dylib" \
    "@executable_path/../Frameworks/libscriptron_ffi.dylib" \
    "$MACOS_DIR/ScripTron" 2>/dev/null || true

install_name_tool \
    -id "@rpath/libscriptron_ffi.dylib" \
    "$FRAMEWORKS_DIR/libscriptron_ffi.dylib"

codesign --force --deep --sign - "$BUNDLE_DIR"

echo "Created $BUNDLE_DIR"
