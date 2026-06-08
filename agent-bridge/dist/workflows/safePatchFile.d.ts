import type { RpcCaller } from '../client/RpcTransport.js';
import type { PatchOptions, SafePatchResult } from '../contracts/types.js';
export declare function safePatchFile(transport: RpcCaller, path: string, unifiedDiff: string, options?: PatchOptions): Promise<SafePatchResult>;
//# sourceMappingURL=safePatchFile.d.ts.map