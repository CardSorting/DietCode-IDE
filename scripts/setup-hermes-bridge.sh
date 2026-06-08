#!/usr/bin/env bash
# Wire Hermes Agent to the DietCode IDE Agent Bridge (production setup).
set -euo pipefail

DIETCODE_IDE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
BRIDGE_CLI="${DIETCODE_IDE_ROOT}/agent-bridge/dist/cli/dietcode-agent-client.js"
APP_PATH="${DIETCODE_IDE_ROOT}/build/DietCode.app/Contents/MacOS/DietCode"

detect_hermes_agent_root() {
  if [[ -n "${HERMES_AGENT_ROOT:-}" && -f "${HERMES_AGENT_ROOT}/plugins/dietcode-plugin/dietcode/plugin.yaml" ]]; then
    printf '%s' "${HERMES_AGENT_ROOT}"
    return 0
  fi
  local candidate
  for candidate in \
    "${DIETCODE_IDE_ROOT}/../hermes-agent-main" \
    "${DIETCODE_IDE_ROOT}/../hermes-agent" \
    "${HOME}/Downloads/hermes-agent-main" \
    "${HERMES_HOME}/hermes-agent"; do
    if [[ -f "${candidate}/plugins/dietcode-plugin/dietcode/plugin.yaml" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

HERMES_AGENT_ROOT="$(detect_hermes_agent_root || true)"
PLUGIN_SRC="${HERMES_AGENT_ROOT}/plugins/dietcode-plugin"

if [[ ! -f "${PLUGIN_SRC}/dietcode/plugin.yaml" ]]; then
  echo "Missing DietCode plugin — set HERMES_AGENT_ROOT to hermes-agent checkout" >&2
  exit 1
fi

echo "→ DietCode IDE: ${DIETCODE_IDE_ROOT}"
echo "→ Hermes agent: ${HERMES_AGENT_ROOT}"
echo "→ Hermes home:  ${HERMES_HOME}"

echo "→ Building agent-bridge"
make -C "${DIETCODE_IDE_ROOT}" agent-bridge-fast

if [[ ! -f "${BRIDGE_CLI}" ]]; then
  echo "Bridge CLI not built: ${BRIDGE_CLI}" >&2
  exit 1
fi

if [[ ! -x "${APP_PATH}" ]]; then
  echo "→ Building DietCode.app (required for --ensure-socket)"
  make -C "${DIETCODE_IDE_ROOT}" app
fi

echo "→ Installing DietCode plugin"
export HERMES_HOME
export DIETCODE_IDE_ROOT
export DIETCODE_BRIDGE_CLI="${BRIDGE_CLI}"
export DIETCODE_APP_PATH="${APP_PATH}"
export DIETCODE_REPO_ROOT="${DIETCODE_IDE_ROOT}"
"${PLUGIN_SRC}/scripts/install-to-hermes.sh"

echo "→ Merging config + IDE bridge runtime"
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
upsert_env "DIETCODE_REPO_ROOT" "${DIETCODE_IDE_ROOT}"
upsert_env "DIETCODE_BRIDGE_CLI" "${BRIDGE_CLI}"
upsert_env "DIETCODE_APP_PATH" "${APP_PATH}"

echo "→ Restarting DietCode agent server"
make -C "${DIETCODE_IDE_ROOT}" restart-agent-server-fast

echo "→ Verifying bridge (wait-ready + profile)"
node "${BRIDGE_CLI}" --wait-ready --compact --app "${APP_PATH}" --workspace "${DIETCODE_IDE_ROOT}"
node "${BRIDGE_CLI}" verify fast --no-start --compact --app "${APP_PATH}" --workspace "${DIETCODE_IDE_ROOT}"

HERMES_BIN="${HERMES_HOME}/bin"
mkdir -p "${HERMES_BIN}"
cat > "${HERMES_BIN}/dietcode-ide-connect" <<'LAUNCHER'
#!/bin/bash
set -euo pipefail
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
IDE_ROOT="${DIETCODE_IDE_ROOT:-$(grep '^DIETCODE_IDE_ROOT=' "$HERMES_HOME/.env" 2>/dev/null | cut -d= -f2-)}"
if [[ -z "${IDE_ROOT}" || ! -f "${IDE_ROOT}/scripts/setup-hermes-bridge.sh" ]]; then
  echo "DIETCODE_IDE_ROOT not configured — run setup from DietCode-IDE checkout" >&2
  exit 1
fi
exec "${IDE_ROOT}/scripts/setup-hermes-bridge.sh" "$@"
LAUNCHER
chmod +x "${HERMES_BIN}/dietcode-ide-connect"
echo "→ Installed ${HERMES_BIN}/dietcode-ide-connect"

chmod +x "${DIETCODE_IDE_ROOT}/scripts/hermes-ide-watchdog.sh"

echo "→ Running Hermes bridge audit"
python3 "${DIETCODE_IDE_ROOT}/scripts/test_hermes_bridge_audit.py" --compact

echo "→ Running Hermes bridge live workflows"
python3 "${DIETCODE_IDE_ROOT}/scripts/test_hermes_bridge_workflows.py" --compact

echo ""
echo "Done. Restart Hermes — session hook auto-connects the IDE bridge."
echo "  hermes plugins list"
echo "  /dietcode doctor"
echo "  /dietcode ide"
echo "  /dietcode ide reconnect"
echo "  make -C ${DIETCODE_IDE_ROOT} hermes-ide-watchdog"
echo ""
echo "Agents: dietcode_ide(action='connect'|'verify'|'search_literal'|'patch'|...)"
