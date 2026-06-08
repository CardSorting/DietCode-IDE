import type { BridgeResult, PartialResultMeta } from './types.js';
export declare function extractPartialMeta(raw: Record<string, unknown>): PartialResultMeta;
export declare function normalizeBridgeResult<T>(raw: Record<string, unknown>, resultKey: string | null, includeRaw?: boolean): BridgeResult<T>;
export declare function normalizeRpcSuccess<T>(envelope: {
    result?: Record<string, unknown>;
}, includeRaw?: boolean): BridgeResult<T>;
export declare function hasPartialSuccessKeys(raw: Record<string, unknown>): boolean;
export declare function assertMutationReceipt(raw: Record<string, unknown>): void;
export declare function assertBatchReceipt(raw: Record<string, unknown>): void;
//# sourceMappingURL=schemas.d.ts.map