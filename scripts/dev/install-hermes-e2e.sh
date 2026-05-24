#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
install_dir="${HERMES_INSTALL_DIR:-$repo_root/.dev/hermes-agent}"
hermes_home="${HERMES_HOME:-$repo_root/.dev/hermes-home}"

mkdir -p "$repo_root/.dev"

curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
  | bash -s -- \
    --skip-setup \
    --skip-browser \
    --dir "$install_dir" \
    --hermes-home "$hermes_home"

echo
echo "Hermes dev install requested."
echo "Use one of these for E2E:"
echo "  export SCRIPTRON_REAL_HERMES_BIN=\"$install_dir/.venv/bin/hermes\""
echo "  export SCRIPTRON_RUN_REAL_HERMES_E2E=1"
echo "  cargo test -p scriptron-core real_hermes_skills_browse_search_hits_official_repository --test hermes_real_e2e -- --nocapture"
