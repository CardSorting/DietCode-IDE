#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q "VERSION = 2" "$ROOT/src/runtime.py"
! grep -q "VERSION = 3" "$ROOT/src/runtime.py"
