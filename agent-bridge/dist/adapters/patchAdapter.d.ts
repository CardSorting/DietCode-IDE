import type { RpcCaller } from '../client/RpcTransport.js';
import type { BatchPatchOptions, BridgeResult, PatchOptions } from '../contracts/types.js';
export interface PatchValidation {
    ok: boolean;
    beforeContentHash: string;
    patchFingerprint: string;
    requiresConfirmation: boolean;
}
export declare function validatePatch(transport: RpcCaller, path: string, unifiedDiff: string): Promise<PatchValidation>;
export declare function applyPatch(transport: RpcCaller, path: string, unifiedDiff: string, expectBeforeHash: string, options?: PatchOptions): Promise<BridgeResult<Record<string, unknown>>>;
export interface BatchPatchRpcEntry {
    path: string;
    patch: string;
    expectBeforeHash: string;
}
export declare function applyPatchBatch(transport: RpcCaller, patches: BatchPatchRpcEntry[], options?: BatchPatchOptions): Promise<BridgeResult<Record<string, unknown>>>;
//# sourceMappingURL=patchAdapter.d.ts.map