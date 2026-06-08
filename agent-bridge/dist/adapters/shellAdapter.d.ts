import type { RpcCaller } from '../client/RpcTransport.js';
import type { BridgeResult } from '../contracts/types.js';
export interface ShellRgOptions {
    path?: string;
    maxResults?: number;
    include?: string[];
    exclude?: string[];
    hidden?: boolean;
    regex?: boolean;
}
export declare function shellPwd(transport: RpcCaller): Promise<BridgeResult<Record<string, unknown>>>;
export declare function shellCd(transport: RpcCaller, path: string): Promise<BridgeResult<Record<string, unknown>>>;
export declare function shellRg(transport: RpcCaller, pattern: string, options?: ShellRgOptions): Promise<BridgeResult<Record<string, unknown>>>;
export declare function shellHead(transport: RpcCaller, path: string, lines?: number): Promise<BridgeResult<Record<string, unknown>>>;
export declare function shellTail(transport: RpcCaller, path: string, lines?: number): Promise<BridgeResult<Record<string, unknown>>>;
export declare function shellSedRange(transport: RpcCaller, path: string, startLine: number, endLine: number): Promise<BridgeResult<Record<string, unknown>>>;
export declare function shellCatSmall(transport: RpcCaller, path: string): Promise<BridgeResult<Record<string, unknown>>>;
//# sourceMappingURL=shellAdapter.d.ts.map