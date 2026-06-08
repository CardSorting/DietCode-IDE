import type { RpcCaller } from '../client/RpcTransport.js';
import type { BridgeResult, SearchOptions } from '../contracts/types.js';
export declare function searchLiteral(transport: RpcCaller, query: string, options?: SearchOptions): Promise<BridgeResult<Record<string, unknown>>>;
export declare function searchTokens(transport: RpcCaller, tokens: string[], options?: SearchOptions): Promise<BridgeResult<Record<string, unknown>>>;
export declare function searchPaths(transport: RpcCaller, query: string, options?: SearchOptions): Promise<BridgeResult<Record<string, unknown>>>;
//# sourceMappingURL=searchAdapter.d.ts.map