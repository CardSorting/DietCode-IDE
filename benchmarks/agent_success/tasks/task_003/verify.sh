#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q 'VALUE = 2' "$ROOT/pkg/a.py"
grep -q 'VALUE = 2' "$ROOT/pkg/b.py"
