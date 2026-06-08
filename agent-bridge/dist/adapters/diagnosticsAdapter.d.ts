import type { RpcCaller } from '../client/RpcTransport.js';
import type { BridgeResult } from '../contracts/types.js';
export declare function fetchDiagnostics(transport: RpcCaller, includeRaw?: boolean): Promise<BridgeResult<Record<string, unknown>>>;
export declare function fetchFileStat(transport: RpcCaller, path: string, includeRaw?: boolean): Promise<BridgeResult<Record<string, unknown>>>;
//# sourceMappingURL=diagnosticsAdapter.d.ts.map