import type { ActivityOptions, BatchPatchOptions, BridgeResult, OperationStatusResult, PatchBatchEntry, PatchOptions, RuntimeProfile, SafeBatchPatchResult, SafePatchResult, SearchOptions, TimelineOptions, TransportOptions, VerifyFastResult } from '../contracts/types.js';
export declare class DietCodeBridgeClient {
    private readonly transport;
    private profile;
    constructor(options?: TransportOptions);
    /** Establish transport and detect runtime capabilities. */
    connect(options?: TransportOptions): Promise<RuntimeProfile>;
    close(): Promise<void>;
    getRuntimeProfile(): RuntimeProfile;
    getDiagnostics(includeRaw?: boolean): Promise<BridgeResult<Record<string, unknown>>>;
    searchLiteral(query: string, options?: SearchOptions): Promise<BridgeResult<Record<string, unknown>>>;
    searchTokens(tokens: string[], options?: SearchOptions): Promise<BridgeResult<Record<string, unknown>>>;
    searchPaths(query: string, options?: SearchOptions): Promise<BridgeResult<Record<string, unknown>>>;
    getFileStat(path: string, includeRaw?: boolean): Promise<BridgeResult<Record<string, unknown>>>;
    safePatchFile(path: string, unifiedDiff: string, options?: PatchOptions): Promise<SafePatchResult>;
    safePatchBatch(patches: PatchBatchEntry[], options?: BatchPatchOptions): Promise<SafeBatchPatchResult>;
    getOperationStatus(idempotencyKey: string): Promise<OperationStatusResult>;
    getTimeline(options?: TimelineOptions): Promise<BridgeResult<Record<string, unknown>>>;
    getRecentActivity(options?: ActivityOptions): Promise<BridgeResult<Record<string, unknown>>>;
    verifyFast(): Promise<VerifyFastResult>;
}
//# sourceMappingURL=DietCodeBridgeClient.d.ts.map