#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
cd "$ROOT" && python3 check.py
! grep -q "return 42" "$ROOT/decoy/handler.py"
