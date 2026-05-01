#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT_DIR/macos/ScripTronNative"

export PATH="/opt/homebrew/opt/rustup/bin:$PATH"

cd "$ROOT_DIR"
cargo build -p scriptron-ffi

cd "$APP_DIR"
swift build

