#!/usr/bin/env bash
# Auto-generated adversarial verify script — checks post-mutation workspace state.
set -euo pipefail

: "${WORKSPACE_ROOT:?WORKSPACE_ROOT is required}"

grep -q "return 'live'" "$WORKSPACE_ROOT/providers/a.py"
! grep -q "return 'live'" "$WORKSPACE_ROOT/providers/b.py"
