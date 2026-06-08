import type { RpcCaller } from '../client/RpcTransport.js';
import type { RpcEnvelope } from '../contracts/types.js';
export declare function waitForApprovalResolution(transport: RpcCaller, approvalId: string, options?: {
    pollMs?: number;
    timeoutMs?: number;
}): Promise<Record<string, unknown>>;
export declare function completeApprovedMutation(transport: RpcCaller, pendingResult: Record<string, unknown>, method: string, params: Record<string, unknown>, options?: {
    pollMs?: number;
    timeoutMs?: number;
}): Promise<RpcEnvelope>;
//# sourceMappingURL=awaitApproval.d.ts.map