#!/usr/bin/env bash
# Sync DietCode Hermes plugin into integrations/ (maintainer boundary — not Hermes core).
set -euo pipefail

DIETCODE_IDE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${DIETCODE_IDE_ROOT}/integrations/hermes-dietcode-plugin"

detect_plugin_src() {
  if [[ -n "${HERMES_PLUGIN_SRC:-}" && -f "${HERMES_PLUGIN_SRC}/plugin.yaml" ]]; then
    printf '%s' "${HERMES_PLUGIN_SRC}"
    return 0
  fi
  local candidate root
  for root in \
    "${HERMES_AGENT_ROOT:-}" \
    "${DIETCODE_IDE_ROOT}/../hermes-agent-main" \
    "${DIETCODE_IDE_ROOT}/../hermes-agent" \
    "${HOME}/Downloads/hermes-agent-main" \
    "${HOME}/.hermes/hermes-agent"; do
    [[ -n "${root}" ]] || continue
    candidate="${root}/plugins/dietcode-plugin/dietcode"
    if [[ -f "${candidate}/plugin.yaml" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  if [[ -f "${DEST}/plugin.yaml" ]]; then
    printf '%s' "${DEST}"
    return 0
  fi
  return 1
}

SRC="$(detect_plugin_src || true)"
if [[ -z "${SRC}" || ! -f "${SRC}/plugin.yaml" ]]; then
  echo "DietCode Hermes plugin source not found." >&2
  echo "Set HERMES_PLUGIN_SRC or HERMES_AGENT_ROOT, or keep integrations/hermes-dietcode-plugin/ populated." >&2
  exit 1
fi

if [[ "$(cd "${SRC}" && pwd)" == "$(cd "${DEST}" 2>/dev/null && pwd || echo "")" ]]; then
  echo "Plugin already at ${DEST}"
  exit 0
fi

mkdir -p "${DEST}"
rsync -a --delete \
  --exclude broccolidb/node_modules \
  --exclude broccolidb/scratch \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "${SRC}/" "${DEST}/"

echo "Synced Hermes plugin → ${DEST}"
