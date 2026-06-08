#!/usr/bin/env bash
# Auto-generated adversarial verify script — checks post-mutation workspace state.
set -euo pipefail

: "${WORKSPACE_ROOT:?WORKSPACE_ROOT is required}"

grep -q "return 42" "$WORKSPACE_ROOT/pkg/impl.py"
grep -q "__all__" "$WORKSPACE_ROOT/pkg/__init__.py"
cd "$WORKSPACE_ROOT" && python3 -c "from pkg import compute; assert compute()==42"
