import type { RpcCaller } from '../client/RpcTransport.js';
import type { ActivityOptions, BridgeResult, OperationStatusResult, TimelineOptions, VerifyFastResult } from '../contracts/types.js';
export declare function fetchTimeline(transport: RpcCaller, options?: TimelineOptions): Promise<BridgeResult<Record<string, unknown>>>;
export declare function fetchRecentActivity(transport: RpcCaller, options?: ActivityOptions): Promise<BridgeResult<Record<string, unknown>>>;
export declare function fetchOperationStatus(transport: RpcCaller, idempotencyKey: string): Promise<OperationStatusResult>;
export declare function verifyFast(transport: RpcCaller): Promise<VerifyFastResult>;
export declare function fetchWorkspaceRevision(transport: RpcCaller): Promise<number>;
//# sourceMappingURL=runtimeAdapter.d.ts.map