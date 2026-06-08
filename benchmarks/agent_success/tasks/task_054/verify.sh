#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q "MAX = 5" "$ROOT/pkg/constants.py"
cd "$ROOT" && python3 -c "from pkg.api import get_max; assert get_max()==5"
