#!/usr/bin/env bash
set -euo pipefail

ACTION=""
PROMPT=""
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --action) ACTION="${2:-}"; shift 2 ;;
        --prompt) PROMPT="${2:-}"; shift 2 ;;
        --project-path|--project_path) PROJECT_PATH="${2:-}"; shift 2 ;;
        *) echo "Unknown parameter: $1" >&2; exit 2 ;;
    esac
done

MODEL_BIN="${EXAMPLE_MODEL_BIN:-$(command -v example-model || true)}"

case "$ACTION" in
    login)
        if [[ -z "$MODEL_BIN" ]]; then
            echo "example-model is not installed. Run './install.sh' first." >&2
            exit 127
        fi
        "$MODEL_BIN" login
        ;;
    chat)
        if [[ -z "$MODEL_BIN" ]]; then
            echo "example-model is not installed. Run './install.sh' first." >&2
            exit 127
        fi
        if [[ -z "$PROMPT" ]]; then
            PROMPT="$(cat)"
        fi
        "$MODEL_BIN" chat --prompt "$PROMPT" ${PROJECT_PATH:+--project "$PROJECT_PATH"}
        ;;
    version)
        if [[ -n "$MODEL_BIN" ]]; then
            "$MODEL_BIN" --version
        else
            echo "example-model not installed"
        fi
        ;;
    *)
        echo "Usage: $0 --action login|chat|version [--prompt text] [--project-path path]" >&2
        exit 2
        ;;
esac
