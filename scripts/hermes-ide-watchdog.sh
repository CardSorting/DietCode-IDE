#!/usr/bin/env bash
# Lightweight DietCode IDE bridge watchdog — reconnect without full reinstall.
set -euo pipefail

DIETCODE_IDE_ROOT="${DIETCODE_IDE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
BRIDGE_CLI="${DIETCODE_IDE_ROOT}/agent-bridge/dist/cli/dietcode-agent-client.js"
APP_PATH="${DIETCODE_IDE_ROOT}/build/DietCode.app/Contents/MacOS/DietCode"

if [[ ! -f "${BRIDGE_CLI}" ]]; then
  echo "Bridge CLI missing — run: make -C ${DIETCODE_IDE_ROOT} agent-bridge-fast" >&2
  exit 1
fi

if [[ -x "${APP_PATH}" ]]; then
  "${APP_PATH}" --ensure-socket --ensure-timeout 10 || true
fi

if ! node "${BRIDGE_CLI}" verify fast --compact --no-start --app "${APP_PATH}" --workspace "${DIETCODE_IDE_ROOT}" 2>/dev/null | grep -q '"ok":true'; then
  echo "→ Bridge unhealthy — running full reconnect"
  exec "${DIETCODE_IDE_ROOT}/scripts/setup-hermes-bridge.sh"
fi

if [[ -f "${HERMES_HOME}/plugins/dietcode/install.py" ]]; then
  python3 "${HERMES_HOME}/plugins/dietcode/install.py" >/dev/null 2>&1 || true
fi

echo '{"ok":true,"action":"watchdog_ok"}'
