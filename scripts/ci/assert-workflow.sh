#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/build.yml"

if [[ ! -f "$workflow" ]]; then
  echo "Missing $workflow" >&2
  exit 1
fi

require() {
  local pattern="$1"
  local message="$2"
  if ! grep -Eq "$pattern" "$workflow"; then
    echo "$message" >&2
    exit 1
  fi
}

reject() {
  local pattern="$1"
  local message="$2"
  if grep -Eq "$pattern" "$workflow"; then
    echo "$message" >&2
    exit 1
  fi
}

require "pull_request:" "CI must run on pull requests."
require "push:" "CI must run on pushes."
require "cargo test --workspace" "CI must run Rust workspace tests."
require "cargo build -p scriptron-ffi" "CI must build the Rust FFI before Swift tests."
require "swift test" "CI must run Swift package tests."
require "macos-" "CI must include a macOS job for the SwiftUI native host."

reject "npm (install|run)" "CI must not use the removed npm/Tauri build pipeline."
reject "src-tauri" "CI must not reference the removed src-tauri directory."
