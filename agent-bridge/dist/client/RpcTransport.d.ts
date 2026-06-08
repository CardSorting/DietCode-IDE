import type { BridgeError, RpcEnvelope, TransportOptions } from '../contracts/types.js';
export declare const CLIENT_SCHEMA_VERSION = "1.6.2";
export declare const DEFAULT_SOCKET_PATH: string;
export declare const DEFAULT_TOKEN_PATH: string;
export interface RpcCaller {
    call(method: string, params?: Record<string, unknown>, options?: {
        requestId?: string;
        timeoutMs?: number;
    }): Promise<RpcEnvelope>;
}
export declare class RpcTransport implements RpcCaller {
    private socket;
    private buffer;
    private readonly pending;
    private token;
    private readonly socketPath;
    private readonly tokenPath;
    private readonly schemaVersion;
    private readonly appPath?;
    private readonly autoStart;
    private defaultTimeoutMs;
    constructor(options?: TransportOptions);
    connect(options?: TransportOptions): Promise<void>;
    close(): Promise<void>;
    call(method: string, params?: Record<string, unknown>, options?: {
        requestId?: string;
        timeoutMs?: number;
    }): Promise<RpcEnvelope>;
    private onData;
    private dispatchFrame;
    private rejectAll;
    private ensureSocket;
    private socketProbe;
}
/** In-memory transport for offline bridge tests. */
export declare class MockRpcTransport implements RpcCaller {
    private readonly handlers;
    calls: Array<{
        method: string;
        params: Record<string, unknown>;
    }>;
    constructor(handlers?: Record<string, (params: Record<string, unknown>) => RpcEnvelope>);
    connect(): Promise<void>;
    close(): Promise<void>;
    call(method: string, params?: Record<string, unknown>): Promise<RpcEnvelope>;
    setHandler(method: string, handler: (params: Record<string, unknown>) => RpcEnvelope): void;
}
export declare function isBridgeError(value: unknown): value is BridgeError;
//# sourceMappingURL=RpcTransport.d.ts.map