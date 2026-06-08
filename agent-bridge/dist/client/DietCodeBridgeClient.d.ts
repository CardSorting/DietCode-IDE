import { type ShellRgOptions } from '../adapters/shellAdapter.js';
import type { ActivityOptions, BatchPatchOptions, BridgeResult, OperationStatusResult, PatchBatchEntry, PatchOptions, RuntimeProfile, SafeBatchPatchResult, SafePatchResult, SearchOptions, TimelineOptions, TransportOptions, VerifyFastResult } from '../contracts/types.js';
export declare class DietCodeBridgeClient {
    private readonly transport;
    private profile;
    private workspacePath;
    private readonly defaultOptions;
    constructor(options?: TransportOptions);
    /** Establish transport, wait for RPC readiness, detect capabilities, optionally open workspace. */
    connect(options?: TransportOptions): Promise<RuntimeProfile>;
    reconnect(options?: TransportOptions): Promise<RuntimeProfile>;
    close(): Promise<void>;
    [Symbol.asyncDispose](): Promise<void>;
    getRuntimeProfile(): RuntimeProfile;
    getWorkspacePath(): string | undefined;
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
    shellPwd(): Promise<BridgeResult<Record<string, unknown>>>;
    shellCd(path: string): Promise<BridgeResult<Record<string, unknown>>>;
    shellRg(pattern: string, options?: ShellRgOptions): Promise<BridgeResult<Record<string, unknown>>>;
    shellHead(path: string, lines?: number): Promise<BridgeResult<Record<string, unknown>>>;
    shellTail(path: string, lines?: number): Promise<BridgeResult<Record<string, unknown>>>;
    shellSedRange(path: string, startLine: number, endLine: number): Promise<BridgeResult<Record<string, unknown>>>;
    shellCatSmall(path: string): Promise<BridgeResult<Record<string, unknown>>>;
}
//# sourceMappingURL=DietCodeBridgeClient.d.ts.map