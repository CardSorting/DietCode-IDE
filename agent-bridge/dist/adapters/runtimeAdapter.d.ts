import type { RpcCaller } from '../client/RpcTransport.js';
import type { ActivityOptions, BridgeResult, OperationStatusResult, TimelineOptions, VerifyFastResult } from '../contracts/types.js';
declare const JOURNAL_AUTHORITY: {
    readonly recordAuthority: "runtime_journal";
    readonly mutationAuthority: "cpp_kernel";
    readonly currentStateAuthority: "workspace_live_read";
    readonly notCurrentFileTruth: true;
};
export declare function applyJournalAuthorityLabels<T extends Record<string, unknown>>(raw: T): T & typeof JOURNAL_AUTHORITY;
export declare function fetchTimeline(transport: RpcCaller, options?: TimelineOptions): Promise<BridgeResult<Record<string, unknown>>>;
export declare function fetchRecentActivity(transport: RpcCaller, options?: ActivityOptions): Promise<BridgeResult<Record<string, unknown>>>;
export declare function fetchOperationStatus(transport: RpcCaller, idempotencyKey: string): Promise<OperationStatusResult>;
export declare function verifyFast(transport: RpcCaller): Promise<VerifyFastResult>;
export declare function fetchWorkspaceRevision(transport: RpcCaller): Promise<number>;
export {};
//# sourceMappingURL=runtimeAdapter.d.ts.map