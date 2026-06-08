#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q "VALUE = 10" "$ROOT/src/runtime.py"
test ! -f "$ROOT/src/runtime.py.bak"
test ! -f "$ROOT/.cache/agent_tmp.json"
