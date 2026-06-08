import type { RpcCaller } from '../client/RpcTransport.js';
import type { RpcEnvelope } from '../contracts/types.js';
export declare function waitForWorkspaceContextRefresh(transport: RpcCaller, timeoutMs?: number): Promise<number>;
export declare function completeAfterWorkspaceRefresh(transport: RpcCaller, driftResult: Record<string, unknown>, method: string, params: Record<string, unknown>, options?: {
    timeoutMs?: number;
}): Promise<RpcEnvelope>;
//# sourceMappingURL=awaitWorkspaceDrift.d.ts.map