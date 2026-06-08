import type { RpcCaller } from '../client/RpcTransport.js';
import type { BatchPatchOptions, PatchBatchEntry, SafeBatchPatchResult } from '../contracts/types.js';
export declare function safePatchBatch(transport: RpcCaller, patches: PatchBatchEntry[], options?: BatchPatchOptions): Promise<SafeBatchPatchResult>;
//# sourceMappingURL=safePatchBatch.d.ts.map