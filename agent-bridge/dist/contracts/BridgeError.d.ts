import type { BridgeErrorCode } from './types.js';
export type RecoverySource = 'runtime' | 'bridge_fallback';
export declare function resolveBridgeRecovery(code: BridgeErrorCode, rawError?: Record<string, unknown>, overrides?: Partial<{
    recoveryHint: string;
    nextRecommendedCommand: string;
    retrySafe: boolean;
}>): {
    recoveryHint: string;
    nextRecommendedCommand: string;
    retrySafe: boolean;
    recoverySource: RecoverySource;
    nextCommandSource: RecoverySource;
};
/** Throwable bridge error with stable recovery metadata. */
export declare class DietCodeBridgeError extends Error {
    readonly code: BridgeErrorCode;
    readonly recoveryHint: string;
    readonly nextRecommendedCommand: string;
    readonly retrySafe: boolean;
    readonly recoverySource: RecoverySource;
    readonly nextCommandSource: RecoverySource;
    readonly rawError?: Record<string, unknown>;
    constructor(code: BridgeErrorCode, message: string, rawError?: Record<string, unknown>, overrides?: Partial<{
        recoveryHint: string;
        nextRecommendedCommand: string;
        retrySafe: boolean;
    }>);
    toJSON(): Record<string, unknown>;
}
export declare function isBridgeError(value: unknown): value is DietCodeBridgeError;
export declare function toBridgeError(value: unknown): DietCodeBridgeError;
//# sourceMappingURL=BridgeError.d.ts.map