const ERROR_RECOVERY = {
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
const PROTECTED_RUNTIME_RECOVERY_CODES = new Set([
    'stale_content',
    'symlink_target',
    'patch_failed',
    'semantic_disabled',
]);
export function resolveBridgeRecovery(code, rawError, overrides) {
    const defaults = ERROR_RECOVERY[code] ?? {
        recoveryHint: 'inspect_bridge_error',
        nextRecommendedCommand: 'runtime.diagnostics',
        retrySafe: false,
    };
    const runtimeHint = (typeof overrides?.recoveryHint === 'string' && overrides.recoveryHint) ||
        (typeof rawError?.recovery_hint === 'string' && rawError.recovery_hint) ||
        undefined;
    const runtimeNext = (typeof overrides?.nextRecommendedCommand === 'string' && overrides.nextRecommendedCommand) ||
        (typeof rawError?.nextRecommendedCommand === 'string' && rawError.nextRecommendedCommand) ||
        undefined;
    const runtimeRetry = typeof overrides?.retrySafe === 'boolean'
        ? overrides.retrySafe
        : typeof rawError?.retryable === 'boolean'
            ? rawError.retryable
            : undefined;
    if (PROTECTED_RUNTIME_RECOVERY_CODES.has(code) && runtimeHint) {
        return {
            recoveryHint: runtimeHint,
            nextRecommendedCommand: runtimeNext ?? defaults.nextRecommendedCommand,
            retrySafe: runtimeRetry ?? defaults.retrySafe,
            recoverySource: 'runtime',
            nextCommandSource: runtimeNext ? 'runtime' : 'bridge_fallback',
        };
    }
    return {
        recoveryHint: runtimeHint ?? defaults.recoveryHint,
        nextRecommendedCommand: runtimeNext ?? defaults.nextRecommendedCommand,
        retrySafe: runtimeRetry ?? defaults.retrySafe,
        recoverySource: runtimeHint ? 'runtime' : 'bridge_fallback',
        nextCommandSource: runtimeNext ? 'runtime' : 'bridge_fallback',
    };
}
/** Throwable bridge error with stable recovery metadata. */
export class DietCodeBridgeError extends Error {
    code;
    recoveryHint;
    nextRecommendedCommand;
    retrySafe;
    recoverySource;
    nextCommandSource;
    rawError;
    constructor(code, message, rawError, overrides) {
        super(message);
        this.name = 'DietCodeBridgeError';
        this.code = code;
        const resolved = resolveBridgeRecovery(code, rawError, overrides);
        this.recoveryHint = resolved.recoveryHint;
        this.nextRecommendedCommand = resolved.nextRecommendedCommand;
        this.retrySafe = resolved.retrySafe;
        this.recoverySource = resolved.recoverySource;
        this.nextCommandSource = resolved.nextCommandSource;
        this.rawError = rawError;
    }
    toJSON() {
        return {
            code: this.code,
            message: this.message,
            recoveryHint: this.recoveryHint,
            nextRecommendedCommand: this.nextRecommendedCommand,
            retrySafe: this.retrySafe,
            recoverySource: this.recoverySource,
            nextCommandSource: this.nextCommandSource,
            rawError: this.rawError,
        };
    }
}
export function isBridgeError(value) {
    return value instanceof DietCodeBridgeError;
}
export function toBridgeError(value) {
    if (value instanceof DietCodeBridgeError) {
        return value;
    }
    if (typeof value === 'object' &&
        value !== null &&
        'code' in value &&
        'message' in value &&
        'recoveryHint' in value) {
        const plain = value;
        return new DietCodeBridgeError(plain.code, plain.message, plain.rawError, {
            recoveryHint: plain.recoveryHint,
            nextRecommendedCommand: plain.nextRecommendedCommand,
            retrySafe: plain.retrySafe,
        });
    }
    return new DietCodeBridgeError('unknown', String(value));
}
//# sourceMappingURL=BridgeError.js.map