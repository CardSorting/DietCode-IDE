import { DietCodeBridgeError } from './BridgeError.js';
const KNOWN_CODES = new Set([
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
    'approval_required',
    'approval_invalid',
    'approval_rejected',
    'approval_timeout',
    'workspace_drift',
]);
export function bridgeError(code, message, rawError, overrides) {
    return new DietCodeBridgeError(code, message, rawError, overrides);
}
export function mapRpcError(envelope, context) {
    const err = envelope.error ?? {
        code: -32000,
        message: context ?? 'RPC call failed',
    };
    const stringCode = (err.string_code ?? 'unknown');
    const code = KNOWN_CODES.has(stringCode) ? stringCode : 'unknown';
    return new DietCodeBridgeError(code, err.message, err, {
        recoveryHint: err.recovery_hint,
        nextRecommendedCommand: err.nextRecommendedCommand,
        retrySafe: err.retryable,
    });
}
export function unsupportedCapabilityError(feature, detail) {
    return new DietCodeBridgeError('unsupported_runtime_capability', `Required runtime capability missing: ${feature} (${detail})`);
}
//# sourceMappingURL=errors.js.map