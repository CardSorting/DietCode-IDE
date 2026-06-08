#!/usr/bin/env bash
# Auto-generated adversarial verify script — checks post-mutation workspace state.
set -euo pipefail

: "${WORKSPACE_ROOT:?WORKSPACE_ROOT is required}"

grep -q "return 42" "$WORKSPACE_ROOT/app.py"
cd "$WORKSPACE_ROOT" && python3 check.py
! grep -q "return 0" "$WORKSPACE_ROOT/app.py"
