#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q "ONE = 'done'" "$ROOT/mods/one.py"
grep -q "TWO = 'done'" "$ROOT/mods/two.py"
grep -q "THREE = 'done'" "$ROOT/mods/three.py"
