#!/usr/bin/env bash
# One-shot script to install deps and build ScripTron on Ubuntu/Debian
set -e

echo "==> Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
  libwebkit2gtk-4.1-dev \
  libgtk-3-dev \
  libayatana-appindicator3-dev \
  librsvg2-dev \
  patchelf

echo "==> Installing npm dependencies..."
npm install

echo "==> Building ScripTron..."
npm run build

echo ""
echo "Done! Find your packages in:"
echo "  AppImage: src-tauri/target/release/bundle/appimage/*.AppImage"
echo "  .deb:     src-tauri/target/release/bundle/deb/*.deb"
