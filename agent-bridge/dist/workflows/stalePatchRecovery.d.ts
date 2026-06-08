import type { RpcCaller } from '../client/RpcTransport.js';
import type { StalePatchRecovery } from '../contracts/types.js';
export declare function buildStaleRecoveryResponse(transport: RpcCaller, path: string, expectedBeforeHash: string, idempotencyKey: string, staleError?: Record<string, unknown>): Promise<StalePatchRecovery>;
//# sourceMappingURL=stalePatchRecovery.d.ts.map