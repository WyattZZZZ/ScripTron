#!/usr/bin/env bash
set -euo pipefail

ACTION=""
INPUT=""
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --action) ACTION="${2:-}"; shift 2 ;;
        --input) INPUT="${2:-}"; shift 2 ;;
        --project-path|--project_path) PROJECT_PATH="${2:-}"; shift 2 ;;
        *) echo "Unknown parameter: $1" >&2; exit 2 ;;
    esac
done

TOOL_BIN="${EXAMPLE_TOOL_BIN:-$(command -v example-tool || true)}"

case "$ACTION" in
    login)
        echo "No login required for example-tool-cli."
        ;;
    run)
        if [[ -z "$TOOL_BIN" ]]; then
            echo "example-tool is not installed. Run './install.sh' first." >&2
            exit 127
        fi
        if [[ -z "$INPUT" ]]; then
            INPUT="$(cat)"
        fi
        "$TOOL_BIN" run --input "$INPUT" ${PROJECT_PATH:+--project "$PROJECT_PATH"}
        ;;
    version)
        if [[ -n "$TOOL_BIN" ]]; then
            "$TOOL_BIN" --version
        else
            echo "example-tool not installed"
        fi
        ;;
    *)
        echo "Usage: $0 --action login|run|version [--input text] [--project-path path]" >&2
        exit 2
        ;;
esac
