#!/usr/bin/env bash
set -euo pipefail

check_absent() {
  local pattern="$1"
  local message="$2"
  shift 2
  if rg -n "$pattern" "$@"; then
    echo "$message" >&2
    exit 1
  fi
}

check_absent \
  "run_task_preview|run_tron_task_preview|runPreview|RunTaskPreview" \
  "Phase 1 requires run cells to use Hermes session/prompt semantics, not one-shot preview runtime APIs." \
  crates/scriptron-core/src crates/scriptron-ffi/src macos/ScripTronNative/Sources macos/ScripTronNative/README.md

check_absent \
  "\\bProviderCard\\b|API Providers|API Provider|store_api_key|disconnect_provider|storeApiKey|disconnectProvider|SecureField\\(\"sk-" \
  "Phase 1 requires model management to be Hermes-managed, without local provider/API-key cards." \
  crates/scriptron-core/src crates/scriptron-ffi/src macos/ScripTronNative/Sources

check_absent \
  "Anthropic|Gemini|OpenAI|DeepSeek|OpenRouter" \
  "Phase 1 docs should not advertise ScripTron-owned model provider setup." \
  readme.md README_zh.md macos/ScripTronNative/README.md
