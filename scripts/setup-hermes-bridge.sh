#!/usr/bin/env bash
# Wire Hermes Agent to the DietCode IDE Agent Bridge (production setup).
set -euo pipefail

DIETCODE_IDE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
BRIDGE_CLI="${DIETCODE_IDE_ROOT}/agent-bridge/dist/cli/dietcode-agent-client.js"
APP_PATH="${DIETCODE_IDE_ROOT}/build/DietCode.app/Contents/MacOS/DietCode"
APP_BUNDLE="${DIETCODE_IDE_ROOT}/build/DietCode.app"

resolve_plugin_src() {
  if [[ -n "${HERMES_PLUGIN_SRC:-}" && -f "${HERMES_PLUGIN_SRC}/plugin.yaml" ]]; then
    printf '%s' "${HERMES_PLUGIN_SRC}"
    return 0
  fi
  if [[ -f "${DIETCODE_IDE_ROOT}/integrations/hermes-dietcode-plugin/plugin.yaml" ]]; then
    printf '%s' "${DIETCODE_IDE_ROOT}/integrations/hermes-dietcode-plugin"
    return 0
  fi
  if [[ -f "${APP_BUNDLE}/Contents/Resources/integrations/hermes/dietcode/plugin.yaml" ]]; then
    printf '%s' "${APP_BUNDLE}/Contents/Resources/integrations/hermes/dietcode"
    return 0
  fi
  local candidate root
  for root in \
    "${HERMES_AGENT_ROOT:-}" \
    "${DIETCODE_IDE_ROOT}/../hermes-agent-main" \
    "${DIETCODE_IDE_ROOT}/../hermes-agent" \
    "${HOME}/Downloads/hermes-agent-main" \
    "${HERMES_HOME}/hermes-agent"; do
    [[ -n "${root}" ]] || continue
    candidate="${root}/plugins/dietcode-plugin/dietcode"
    if [[ -f "${candidate}/plugin.yaml" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

PLUGIN_SRC="$(resolve_plugin_src || true)"
if [[ -z "${PLUGIN_SRC}" ]]; then
  echo "→ Syncing Hermes plugin into integrations/"
  "${DIETCODE_IDE_ROOT}/scripts/sync-hermes-plugin.sh"
  PLUGIN_SRC="${DIETCODE_IDE_ROOT}/integrations/hermes-dietcode-plugin"
fi

if [[ ! -f "${PLUGIN_SRC}/plugin.yaml" ]]; then
  echo "Missing DietCode Hermes plugin." >&2
  echo "Run: ./scripts/sync-hermes-plugin.sh  or  ./scripts/enable-hermes-agent.sh" >&2
  exit 1
fi

echo "→ DietCode IDE: ${DIETCODE_IDE_ROOT}"
echo "→ Plugin source: ${PLUGIN_SRC}"
echo "→ Hermes home:  ${HERMES_HOME}"

echo "→ Building agent-bridge"
make -C "${DIETCODE_IDE_ROOT}" agent-bridge-fast

if [[ ! -f "${BRIDGE_CLI}" ]]; then
  echo "Bridge CLI not built: ${BRIDGE_CLI}" >&2
  exit 1
fi

if [[ ! -x "${APP_PATH}" ]]; then
  echo "→ Building DietCode.app (bridge + Hermes plugin bundle)"
  make -C "${DIETCODE_IDE_ROOT}" app
  BRIDGE_CLI="${APP_BUNDLE}/Contents/Resources/bin/dietcode-agent-client"
fi

echo "→ Enabling Hermes agent (lazy install + plugin deploy)"
export HERMES_HOME
export DIETCODE_IDE_ROOT
export DIETCODE_APP_BUNDLE="${APP_BUNDLE}"
export DIETCODE_BRIDGE_CLI="${BRIDGE_CLI}"
export DIETCODE_APP_PATH="${APP_PATH}"
export HERMES_PLUGIN_SRC="${PLUGIN_SRC}"
"${DIETCODE_IDE_ROOT}/scripts/enable-hermes-agent.sh"

echo "→ Restarting DietCode agent server"
make -C "${DIETCODE_IDE_ROOT}" restart-agent-server-fast

echo "→ Verifying bridge (wait-ready + profile)"
if [[ -f "${APP_BUNDLE}/Contents/Resources/bin/dietcode-agent-client" ]]; then
  BRIDGE_CLI="${APP_BUNDLE}/Contents/Resources/bin/dietcode-agent-client"
fi
"${BRIDGE_CLI}" --wait-ready --compact --app "${APP_PATH}" --workspace "${DIETCODE_IDE_ROOT}" 2>/dev/null \
  || node "${BRIDGE_CLI}" --wait-ready --compact --app "${APP_PATH}" --workspace "${DIETCODE_IDE_ROOT}"
"${BRIDGE_CLI}" verify fast --no-start --compact --app "${APP_PATH}" --workspace "${DIETCODE_IDE_ROOT}" 2>/dev/null \
  || node "${BRIDGE_CLI}" verify fast --no-start --compact --app "${APP_PATH}" --workspace "${DIETCODE_IDE_ROOT}"

HERMES_BIN="${HERMES_HOME}/bin"
mkdir -p "${HERMES_BIN}"
cat > "${HERMES_BIN}/dietcode-ide-connect" <<'LAUNCHER'
#!/bin/bash
set -euo pipefail
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
IDE_ROOT="${DIETCODE_IDE_ROOT:-$(grep '^DIETCODE_IDE_ROOT=' "$HERMES_HOME/.env" 2>/dev/null | cut -d= -f2-)}"
APP_BUNDLE="${DIETCODE_APP_BUNDLE:-$(grep '^DIETCODE_APP_BUNDLE=' "$HERMES_HOME/.env" 2>/dev/null | cut -d= -f2-)}"
if [[ -n "${APP_BUNDLE}" && -f "${APP_BUNDLE}/Contents/Resources/bin/dietcode-enable-agent" ]]; then
  exec "${APP_BUNDLE}/Contents/Resources/bin/dietcode-enable-agent" "$@"
fi
if [[ -n "${IDE_ROOT}" && -f "${IDE_ROOT}/scripts/enable-hermes-agent.sh" ]]; then
  exec "${IDE_ROOT}/scripts/enable-hermes-agent.sh" "$@"
fi
if [[ -n "${IDE_ROOT}" && -f "${IDE_ROOT}/scripts/setup-hermes-bridge.sh" ]]; then
  exec "${IDE_ROOT}/scripts/setup-hermes-bridge.sh" "$@"
fi
echo "DietCode not configured — install DietCode.app or set DIETCODE_IDE_ROOT" >&2
exit 1
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
echo "  dietcode-enable-agent   (from DietCode.app, no checkout)"
echo "  make -C ${DIETCODE_IDE_ROOT} hermes-ide-watchdog"
echo ""
echo "Agents: dietcode_ide(action='connect'|'verify'|'search_literal'|'patch'|...)"
