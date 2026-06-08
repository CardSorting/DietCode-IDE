#!/usr/bin/env bash
# Auto-generated adversarial verify script — checks post-mutation workspace state.
set -euo pipefail

: "${WORKSPACE_ROOT:?WORKSPACE_ROOT is required}"

grep -q "VALUE = 2" "$WORKSPACE_ROOT/src/module.py"
grep -q "FLAG_OK = True" "$WORKSPACE_ROOT/src/module.py"
grep -q "correct header" "$WORKSPACE_ROOT/src/module.py"
