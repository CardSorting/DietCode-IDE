#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q "ANCHOR_TASK_009=done" "$ROOT/data/small_anchor.txt"
