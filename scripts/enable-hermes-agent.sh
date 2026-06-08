#!/usr/bin/env bash
# Enable Hermes Agent for DietCode — lazy-install Hermes + deploy bundled plugin.
set -euo pipefail

DIETCODE_IDE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"

resolve_app_bundle() {
  if [[ -n "${DIETCODE_APP_BUNDLE:-}" && -d "${DIETCODE_APP_BUNDLE}/Contents/MacOS" ]]; then
    printf '%s' "${DIETCODE_APP_BUNDLE}"
    return 0
  fi
  local candidate
  for candidate in \
    "${DIETCODE_IDE_ROOT}/build/DietCode.app" \
    "/Applications/DietCode.app" \
    "${HOME}/Applications/DietCode.app"; do
    if [[ -d "${candidate}/Contents/MacOS" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

resolve_plugin_src() {
  local bundle="${1:-}"
  if [[ -n "${bundle}" && -f "${bundle}/Contents/Resources/integrations/hermes/dietcode/plugin.yaml" ]]; then
    printf '%s' "${bundle}/Contents/Resources/integrations/hermes/dietcode"
    return 0
  fi
  if [[ -f "${DIETCODE_IDE_ROOT}/integrations/hermes-dietcode-plugin/plugin.yaml" ]]; then
    printf '%s' "${DIETCODE_IDE_ROOT}/integrations/hermes-dietcode-plugin"
    return 0
  fi
  if [[ -n "${HERMES_PLUGIN_SRC:-}" && -f "${HERMES_PLUGIN_SRC}/plugin.yaml" ]]; then
    printf '%s' "${HERMES_PLUGIN_SRC}"
    return 0
  fi
  if [[ -f "${DIETCODE_IDE_ROOT}/scripts/sync-hermes-plugin.sh" ]]; then
    "${DIETCODE_IDE_ROOT}/scripts/sync-hermes-plugin.sh" >/dev/null
    if [[ -f "${DIETCODE_IDE_ROOT}/integrations/hermes-dietcode-plugin/plugin.yaml" ]]; then
      printf '%s' "${DIETCODE_IDE_ROOT}/integrations/hermes-dietcode-plugin"
      return 0
    fi
  fi
  return 1
}

ensure_hermes_cli() {
  if command -v hermes >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "${HERMES_HOME}/bin/hermes" ]]; then
    export PATH="${HERMES_HOME}/bin:${PATH}"
    return 0
  fi
  echo "→ Installing Hermes Agent to ${HERMES_HOME}"
  curl -fsSL "${HERMES_INSTALL_URL}" | bash -s -- --skip-setup
  export PATH="${HERMES_HOME}/bin:${PATH}"
}

APP_BUNDLE="$(resolve_app_bundle || true)"
PLUGIN_SRC="$(resolve_plugin_src "${APP_BUNDLE}" || true)"
if [[ -z "${PLUGIN_SRC}" ]]; then
  echo "DietCode Hermes plugin not found in app bundle or integrations/." >&2
  echo "Run: ./scripts/sync-hermes-plugin.sh && make app" >&2
  exit 1
fi

if [[ -n "${APP_BUNDLE}" ]]; then
  APP_PATH="${APP_BUNDLE}/Contents/MacOS/DietCode"
  BRIDGE_CLI="${APP_BUNDLE}/Contents/Resources/bin/dietcode-agent-client"
  IDE_ROOT="${APP_BUNDLE}"
else
  APP_PATH="${DIETCODE_IDE_ROOT}/build/DietCode.app/Contents/MacOS/DietCode"
  BRIDGE_CLI="${DIETCODE_IDE_ROOT}/agent-bridge/dist/cli/dietcode-agent-client.js"
  IDE_ROOT="${DIETCODE_IDE_ROOT}"
fi

if [[ ! -f "${BRIDGE_CLI}" ]]; then
  echo "Bridge CLI missing — run: make -C ${DIETCODE_IDE_ROOT} app" >&2
  exit 1
fi

ensure_hermes_cli

DEST="${HERMES_HOME}/plugins/dietcode"
mkdir -p "${HERMES_HOME}/plugins"
echo "→ Deploying plugin from ${PLUGIN_SRC}"
rsync -a --delete \
  --exclude broccolidb/node_modules \
  --exclude broccolidb/scratch \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "${PLUGIN_SRC}/" "${DEST}/"

export HERMES_HOME
export DIETCODE_IDE_ROOT="${IDE_ROOT}"
export DIETCODE_REPO_ROOT="${IDE_ROOT}"
export DIETCODE_APP_PATH="${APP_PATH}"
export DIETCODE_APP_BUNDLE="${APP_BUNDLE:-}"
export DIETCODE_BRIDGE_CLI="${BRIDGE_CLI}"

echo "→ Merging Hermes config + IDE bridge runtime"
python3 "${DEST}/install.py"

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

upsert_env "DIETCODE_IDE_ROOT" "${IDE_ROOT}"
upsert_env "DIETCODE_REPO_ROOT" "${IDE_ROOT}"
upsert_env "DIETCODE_APP_PATH" "${APP_PATH}"
upsert_env "DIETCODE_BRIDGE_CLI" "${BRIDGE_CLI}"
if [[ -n "${APP_BUNDLE}" ]]; then
  upsert_env "DIETCODE_APP_BUNDLE" "${APP_BUNDLE}"
fi

if [[ -x "${APP_PATH}" ]]; then
  echo "→ Ensuring DietCode control socket"
  "${APP_PATH}" --ensure-socket --ensure-timeout 15 || true
fi

if command -v node >/dev/null 2>&1; then
  echo "→ Verifying bridge"
  node "${BRIDGE_CLI}" verify fast --compact --no-start --app "${APP_PATH}" 2>/dev/null \
    || "${BRIDGE_CLI}" verify fast --compact --no-start --app "${APP_PATH}" 2>/dev/null \
    || true
fi

echo ""
echo "Hermes agent enabled for DietCode."
echo "  Restart Hermes, then: /dietcode doctor   and   /dietcode ide"
echo "  Plugin: ${DEST}"
echo "  Bridge: ${BRIDGE_CLI}"
