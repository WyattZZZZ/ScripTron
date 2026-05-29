#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
install_dir="${HERMES_INSTALL_DIR:-$repo_root/.dev/hermes-agent}"
hermes_home="${HERMES_HOME:-$repo_root/.dev/hermes-home}"
github_mirror_prefix="${GITHUB_MIRROR_PREFIX:-https://gh-proxy.com/}"
install_script_url="${HERMES_INSTALL_SCRIPT_URL:-${github_mirror_prefix}https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"

mkdir -p "$repo_root/.dev"

echo "Fetching Hermes installer from:"
echo "  $install_script_url"

curl -fsSL "$install_script_url" \
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
