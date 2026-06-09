import type { RpcCaller } from '../client/RpcTransport.js';
import type { CoherenceOperatorRequired, CoherenceRecoveryEvent, CoherenceStaleRecovery, CoherenceToken } from '../contracts/types.js';
export interface CoherenceMismatchDetail {
    reason: string;
    changedPaths: string[];
    requiredAction?: string;
    currentWorkspaceRevision?: number;
}
export declare function parseCoherenceMismatch(rawError?: Record<string, unknown>): CoherenceMismatchDetail;
export declare function buildCoherenceStaleRecovery(path: string, idempotencyKey: string, detail: CoherenceMismatchDetail, rawError?: Record<string, unknown>): CoherenceStaleRecovery;
export declare function buildCoherenceOperatorRequired(path: string, idempotencyKey: string, detail: CoherenceMismatchDetail, rawError?: Record<string, unknown>): CoherenceOperatorRequired;
export declare function refreshCoherenceContext(transport: RpcCaller, taskId: string, paths: string[], emit?: (event: CoherenceRecoveryEvent) => void): Promise<{
    path: string;
    text: string;
    coherence: CoherenceToken;
}>;
//# sourceMappingURL=coherenceRecovery.d.ts.map