#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q "OLD_VALUE = 3" "$ROOT/src/active.py"
! grep -q "OLD_VALUE = 3" "$ROOT/shadow/indexed_copy.py"
