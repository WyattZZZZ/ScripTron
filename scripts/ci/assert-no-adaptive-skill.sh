#!/usr/bin/env bash
set -euo pipefail

if rg -n "adaptive_skill|Adaptive Skill|Skill Retry|skill_retry|SkillRetry|runAdaptiveSkillTrace|skillTrace" \
  --glob '!target/**' \
  --glob '!.build/**' \
  --glob '!scripts/ci/assert-no-adaptive-skill.sh' \
  .; then
  echo "Adaptive skill self-repair has been removed; route skill calls through Hermes Agent instead." >&2
  exit 1
fi
