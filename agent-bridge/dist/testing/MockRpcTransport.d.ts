import type { RpcCaller } from '../client/RpcTransport.js';
import type { RpcEnvelope } from '../contracts/types.js';
/** Test-only in-memory RPC transport. Not for production agent use. */
export declare class MockRpcTransport implements RpcCaller {
    private readonly handlers;
    calls: Array<{
        method: string;
        params: Record<string, unknown>;
    }>;
    constructor(handlers?: Record<string, (params: Record<string, unknown>) => RpcEnvelope | Promise<RpcEnvelope>>);
    connect(): Promise<void>;
    close(): Promise<void>;
    call(method: string, params?: Record<string, unknown>): Promise<RpcEnvelope>;
    setHandler(method: string, handler: (params: Record<string, unknown>) => RpcEnvelope | Promise<RpcEnvelope>): void;
}
//# sourceMappingURL=MockRpcTransport.d.ts.map