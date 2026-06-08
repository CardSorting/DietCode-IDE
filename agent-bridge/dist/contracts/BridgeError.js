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
/** Throwable bridge error with stable recovery metadata. */
export class DietCodeBridgeError extends Error {
    code;
    recoveryHint;
    nextRecommendedCommand;
    retrySafe;
    rawError;
    constructor(code, message, rawError, overrides) {
        super(message);
        this.name = 'DietCodeBridgeError';
        this.code = code;
        const defaults = ERROR_RECOVERY[code] ?? {
            recoveryHint: 'inspect_bridge_error',
            nextRecommendedCommand: 'runtime.diagnostics',
            retrySafe: false,
        };
        this.recoveryHint = overrides?.recoveryHint ?? defaults.recoveryHint;
        this.nextRecommendedCommand = overrides?.nextRecommendedCommand ?? defaults.nextRecommendedCommand;
        this.retrySafe = overrides?.retrySafe ?? defaults.retrySafe;
        this.rawError = rawError;
    }
    toJSON() {
        return {
            code: this.code,
            message: this.message,
            recoveryHint: this.recoveryHint,
            nextRecommendedCommand: this.nextRecommendedCommand,
            retrySafe: this.retrySafe,
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