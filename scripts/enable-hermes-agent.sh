#!/usr/bin/env bash
# Enable Hermes Agent for DietCode — delegates to dietcode_enable_agent.py.
set -euo pipefail
DIETCODE_IDE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "${DIETCODE_IDE_ROOT}/scripts/dietcode_enable_agent.py" "$@"
