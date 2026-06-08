import type { TransportOptions } from '../contracts/types.js';
export declare const CLIENT_SCHEMA_VERSION = "1.6.2";
export declare const BRIDGE_PACKAGE_VERSION = "1.0.0";
export declare const DEFAULT_SOCKET_PATH: string;
export declare const DEFAULT_TOKEN_PATH: string;
export declare const MAX_REQUEST_BYTES: number;
export declare const MAX_RESPONSE_BYTES: number;
export interface ResolvedTransportConfig {
    socketPath: string;
    tokenPath: string;
    schemaVersion: string;
    appPath?: string;
    startApp: boolean;
    connectTimeoutMs: number;
    requestTimeoutMs: number;
    transportRetries: number;
    agentId?: string;
    rationale?: string;
    workspaceRoot?: string;
}
export declare function isReadMethod(method: string): boolean;
export declare function resolveTransportConfig(options?: TransportOptions): ResolvedTransportConfig;
export declare function resolveAppPath(explicit?: string): string | undefined;
//# sourceMappingURL=config.d.ts.map