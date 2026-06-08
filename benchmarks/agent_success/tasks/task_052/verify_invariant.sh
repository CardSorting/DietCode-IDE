#!/usr/bin/env bash
# Auto-generated adversarial verify script — checks post-mutation workspace state.
set -euo pipefail

: "${WORKSPACE_ROOT:?WORKSPACE_ROOT is required}"

cd "$WORKSPACE_ROOT" && python3 -c "from src.status import invariant_ok; assert invariant_ok()"
