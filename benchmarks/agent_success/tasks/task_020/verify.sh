#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q "a = 'closed'" "$ROOT/verify/multi_a.py"
grep -q "b = 'closed'" "$ROOT/verify/multi_b.py"
