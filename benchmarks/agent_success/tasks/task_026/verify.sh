#!/usr/bin/env bash
# Auto-generated adversarial verify script — checks post-mutation workspace state.
set -euo pipefail

: "${WORKSPACE_ROOT:?WORKSPACE_ROOT is required}"

grep -q "status = 'ready'" "$WORKSPACE_ROOT/worker.py"
