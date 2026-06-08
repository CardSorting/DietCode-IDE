import type { RpcCaller } from './RpcTransport.js';
import type { TransportOptions } from '../contracts/types.js';
export interface ReadyState {
    ok: boolean;
    socketPath: string;
    tokenPath: string;
    rpcReady: boolean;
    latencyMs: number;
}
export declare function waitForReady(transport: RpcCaller, options?: {
    timeoutMs?: number;
    intervalMs?: number;
}): Promise<ReadyState>;
export declare function resolveConnectOptions(options?: TransportOptions): TransportOptions;
//# sourceMappingURL=connection.d.ts.map