#!/bin/bash
# Auto-generated verify script — checks post-mutation workspace state.
set -euo pipefail
ROOT="${WORKSPACE_ROOT:?WORKSPACE_ROOT required}"
grep -q "TASK_010_HEADER=done" "$ROOT/logs/header.txt"
