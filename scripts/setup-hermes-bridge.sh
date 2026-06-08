#!/usr/bin/env bash
# Wire Hermes Agent to the DietCode IDE Agent Bridge.
set -euo pipefail

DIETCODE_IDE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_AGENT_ROOT="${HERMES_AGENT_ROOT:-/Users/bozoegg/Downloads/hermes-agent-main}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
PLUGIN_SRC="${HERMES_AGENT_ROOT}/plugins/dietcode-plugin"
BRIDGE_CLI="${DIETCODE_IDE_ROOT}/agent-bridge/dist/cli/dietcode-agent-client.js"
APP_PATH="${DIETCODE_IDE_ROOT}/build/DietCode.app/Contents/MacOS/DietCode"

if [[ ! -f "${PLUGIN_SRC}/dietcode/plugin.yaml" ]]; then
  echo "Missing DietCode plugin at ${PLUGIN_SRC}" >&2
  exit 1
fi

echo "→ Building agent-bridge in ${DIETCODE_IDE_ROOT}"
make -C "${DIETCODE_IDE_ROOT}" agent-bridge-fast

if [[ ! -f "${BRIDGE_CLI}" ]]; then
  echo "Bridge CLI not built: ${BRIDGE_CLI}" >&2
  exit 1
fi

echo "→ Installing DietCode plugin to ${HERMES_HOME}/plugins/dietcode"
export HERMES_HOME
export DIETCODE_IDE_ROOT
export DIETCODE_BRIDGE_CLI="${BRIDGE_CLI}"
export DIETCODE_APP_PATH="${APP_PATH}"
"${PLUGIN_SRC}/scripts/install-to-hermes.sh"

echo "→ Merging IDE bridge config"
python3 "${HERMES_HOME}/plugins/dietcode/install.py"

ENV_FILE="${HERMES_HOME}/.env"
touch "${ENV_FILE}"

upsert_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
    else
      sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
    fi
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi
}

upsert_env "DIETCODE_IDE_ROOT" "${DIETCODE_IDE_ROOT}"
upsert_env "DIETCODE_BRIDGE_CLI" "${BRIDGE_CLI}"
upsert_env "DIETCODE_APP_PATH" "${APP_PATH}"

echo "→ Ensuring DietCode runtime socket"
if [[ -x "${APP_PATH}" ]]; then
  "${APP_PATH}" --ensure-socket --ensure-timeout 15 || true
fi

echo "→ Verifying bridge"
node "${BRIDGE_CLI}" verify fast --no-start --compact --app "${APP_PATH}"

echo ""
echo "Done. Restart Hermes, then verify:"
echo "  hermes plugins list"
echo "  /dietcode doctor"
echo ""
echo "Hermes agents can use the dietcode_ide tool for IDE-backed search and safe patches."
