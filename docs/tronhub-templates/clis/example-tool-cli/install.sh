#!/usr/bin/env bash
set -euo pipefail

echo "Installing example tool CLI dependencies..."

if [[ -n "${EXAMPLE_TOOL_BIN:-}" && -x "${EXAMPLE_TOOL_BIN}" ]]; then
    echo "Using EXAMPLE_TOOL_BIN=${EXAMPLE_TOOL_BIN}"
    echo "Installation complete."
    exit 0
fi

if command -v example-tool >/dev/null 2>&1; then
    echo "example-tool is already available at $(command -v example-tool)."
    echo "Installation complete."
    exit 0
fi

cat >&2 <<'EOF'
Error: example-tool was not found.

Install the external dependency here, or set EXAMPLE_TOOL_BIN to an executable path.
Keep dependency installation in this file so ScripTron can run it with one click.
EOF
exit 127
