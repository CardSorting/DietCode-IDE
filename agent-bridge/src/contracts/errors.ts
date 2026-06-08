import type { BridgeError, BridgeErrorCode, RpcEnvelope, RpcErrorPayload } from './types.js';

const ERROR_RECOVERY: Record<string, { recoveryHint: string; nextRecommendedCommand: string; retrySafe: boolean }> = {
  stale_content: {
    recoveryHint: 'revalidate_patch_with_patch.validate',
    nextRecommendedCommand: 'patch.validate',
    retrySafe: false,
  },
  semantic_disabled: {
    recoveryHint: 'use_search_literal_or_search_tokens',
    nextRecommendedCommand: 'search.literal',
    retrySafe: false,
  },
  ranked_search_disabled: {
    recoveryHint: 'use_workspace_grep_or_search_literal',
    nextRecommendedCommand: 'workspace.grep',
    retrySafe: false,
  },
  symlink_target: {
    recoveryHint: 'use_non_symlink_target_path',
    nextRecommendedCommand: 'file.stat',
    retrySafe: false,
  },
  patch_failed: {
    recoveryHint: 'run_patch_preview_or_patch_validate',
    nextRecommendedCommand: 'patch.validate',
    retrySafe: false,
  },
  nested_call_timeout: {
    recoveryHint: 'reduce_concurrency_or_retry_later',
    nextRecommendedCommand: 'operation.status',
    retrySafe: true,
  },
  runtime_unavailable: {
    recoveryHint: 'retry_runtime_diagnostics',
    nextRecommendedCommand: 'runtime.diagnostics',
    retrySafe: true,
  },
  unsupported_runtime_capability: {
    recoveryHint: 'upgrade_dietcode_runtime',
    nextRecommendedCommand: 'runtime.diagnostics',
    retrySafe: false,
  },
  transport_error: {
    recoveryHint: 'dietcode_agent_client.py --diagnose',
    nextRecommendedCommand: 'runtime.diagnostics',
    retrySafe: true,
  },
  invalid_params: {
    recoveryHint: 'fix_request_params',
    nextRecommendedCommand: 'runtime.diagnostics',
    retrySafe: false,
  },
};

const KNOWN_CODES = new Set<string>(Object.keys(ERROR_RECOVERY));

export function bridgeError(
  code: BridgeErrorCode,
  message: string,
  rawError?: Record<string, unknown>,
  overrides?: Partial<Pick<BridgeError, 'recoveryHint' | 'nextRecommendedCommand' | 'retrySafe'>>,
): BridgeError {
  const defaults = ERROR_RECOVERY[code] ?? {
    recoveryHint: 'inspect_bridge_error',
    nextRecommendedCommand: 'runtime.diagnostics',
    retrySafe: false,
  };
  return {
    code,
    message,
    recoveryHint: overrides?.recoveryHint ?? defaults.recoveryHint,
    nextRecommendedCommand: overrides?.nextRecommendedCommand ?? defaults.nextRecommendedCommand,
    retrySafe: overrides?.retrySafe ?? defaults.retrySafe,
    rawError,
  };
}

export function mapRpcError(envelope: RpcEnvelope, context?: string): BridgeError {
  const err: RpcErrorPayload = envelope.error ?? {
    code: -32000,
    message: context ?? 'RPC call failed',
  };
  const stringCode = (err.string_code ?? 'unknown') as BridgeErrorCode;
  const code: BridgeErrorCode = KNOWN_CODES.has(stringCode) ? stringCode : 'unknown';
  return bridgeError(
    code,
    err.message,
    err as unknown as Record<string, unknown>,
    {
      recoveryHint: err.recovery_hint,
      nextRecommendedCommand: err.nextRecommendedCommand,
      retrySafe: err.retryable ?? (ERROR_RECOVERY[code]?.retrySafe ?? false),
    },
  );
}

export function unsupportedCapabilityError(feature: string, detail: string): BridgeError {
  return bridgeError(
    'unsupported_runtime_capability',
    `Required runtime capability missing: ${feature} (${detail})`,
  );
}
