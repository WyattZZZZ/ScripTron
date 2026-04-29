#!/usr/bin/env bash
# Build ScripTron on macOS → produces a universal .dmg (Intel + Apple Silicon)
set -e

if [[ "$(uname)" != "Darwin" ]]; then
  echo "ERROR: This script must run on macOS. Cross-compiling to macOS from Linux is not supported."
  echo "       Use GitHub Actions (push to GitHub → Actions tab → Run workflow) instead."
  exit 1
fi

echo "==> Adding Rust targets..."
rustup target add aarch64-apple-darwin x86_64-apple-darwin

echo "==> Installing npm dependencies..."
npm install

echo "==> Building universal binary (Intel + Apple Silicon)..."
npm run build -- --target universal-apple-darwin

echo ""
echo "Done! Your installer is at:"
echo "  src-tauri/target/universal-apple-darwin/release/bundle/dmg/ScripTron_0.1.0_universal.dmg"
