import { DietCodeBridgeError } from './BridgeError.js';
import type { BridgeErrorCode, RpcEnvelope, RpcErrorPayload } from './types.js';

const KNOWN_CODES = new Set<string>([
  'stale_content',
  'semantic_disabled',
  'ranked_search_disabled',
  'symlink_target',
  'patch_failed',
  'nested_call_timeout',
  'runtime_unavailable',
  'unsupported_runtime_capability',
  'transport_error',
  'invalid_params',
]);

export function bridgeError(
  code: BridgeErrorCode,
  message: string,
  rawError?: Record<string, unknown>,
  overrides?: Partial<{
    recoveryHint: string;
    nextRecommendedCommand: string;
    retrySafe: boolean;
  }>,
): DietCodeBridgeError {
  return new DietCodeBridgeError(code, message, rawError, overrides);
}

export function mapRpcError(envelope: RpcEnvelope, context?: string): DietCodeBridgeError {
  const err: RpcErrorPayload = envelope.error ?? {
    code: -32000,
    message: context ?? 'RPC call failed',
  };
  const stringCode = (err.string_code ?? 'unknown') as BridgeErrorCode;
  const code: BridgeErrorCode = KNOWN_CODES.has(stringCode) ? stringCode : 'unknown';
  return new DietCodeBridgeError(code, err.message, err as unknown as Record<string, unknown>, {
    recoveryHint: err.recovery_hint,
    nextRecommendedCommand: err.nextRecommendedCommand,
    retrySafe: err.retryable,
  });
}

export function unsupportedCapabilityError(feature: string, detail: string): DietCodeBridgeError {
  return new DietCodeBridgeError(
    'unsupported_runtime_capability',
    `Required runtime capability missing: ${feature} (${detail})`,
  );
}
