#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q "FLAG = 'fixed'" "$ROOT/src/core.py"
test -f "$ROOT/generated/important.snapshot"
