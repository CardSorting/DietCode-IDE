import { isBridgeError } from '../contracts/BridgeError.js';
import type { RpcEnvelope, TransportOptions } from '../contracts/types.js';
export { CLIENT_SCHEMA_VERSION, DEFAULT_SOCKET_PATH, DEFAULT_TOKEN_PATH } from './config.js';
export interface RpcCaller {
    call(method: string, params?: Record<string, unknown>, options?: {
        requestId?: string;
        timeoutMs?: number;
        agentId?: string;
        rationale?: string;
    }): Promise<RpcEnvelope>;
    connect(options?: TransportOptions): Promise<void>;
    close(): Promise<void>;
}
export declare class RpcTransport implements RpcCaller {
    private socket;
    private buffer;
    private token;
    private readonly config;
    private callChain;
    private closed;
    constructor(options?: TransportOptions);
    connect(options?: TransportOptions): Promise<void>;
    close(): Promise<void>;
    reconnect(options?: TransportOptions): Promise<void>;
    call(method: string, params?: Record<string, unknown>, options?: {
        requestId?: string;
        timeoutMs?: number;
        agentId?: string;
        rationale?: string;
    }): Promise<RpcEnvelope>;
    private callUnlocked;
    private sendAndReceive;
    private readJsonFrame;
    private readSocketChunk;
    private ensureSocket;
    private socketProbe;
}
export { isBridgeError };
//# sourceMappingURL=RpcTransport.d.ts.map