#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q "TIMEOUT_MS = 2500" "$ROOT/src/runtime/live_config.py"
! grep -q "TIMEOUT_MS = 2500" "$ROOT/src/legacy_config.py"
cd "$ROOT" && python3 scripts/trace_config.py | grep -q "src/runtime/live_config.py"
