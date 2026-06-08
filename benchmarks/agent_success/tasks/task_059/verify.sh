#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
cd "$ROOT" && python3 test_api.py
grep -q "def format_result" "$ROOT/lib/public.py"
grep -q "def compute" "$ROOT/lib/public.py"
