#!/usr/bin/env bash
set -euo pipefail

echo "Installing example model provider dependencies..."

if [[ -n "${EXAMPLE_MODEL_BIN:-}" && -x "${EXAMPLE_MODEL_BIN}" ]]; then
    echo "Using EXAMPLE_MODEL_BIN=${EXAMPLE_MODEL_BIN}"
    echo "Installation complete. Run './run.sh --action login' to authenticate."
    exit 0
fi

if command -v example-model >/dev/null 2>&1; then
    echo "example-model is already available at $(command -v example-model)."
    echo "Installation complete. Run './run.sh --action login' to authenticate."
    exit 0
fi

cat >&2 <<'EOF'
Error: example-model was not found.

Install your provider CLI here, or set EXAMPLE_MODEL_BIN to an executable path.
Keep dependency installation in this file so ScripTron can run it with one click.
EOF
exit 127
