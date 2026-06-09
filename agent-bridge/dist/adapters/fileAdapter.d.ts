import type { RpcCaller } from '../client/RpcTransport.js';
import type { CoherenceToken } from '../contracts/types.js';
export declare function readFileWithCoherence(transport: RpcCaller, path: string, taskId: string): Promise<{
    text: string;
    coherence: CoherenceToken;
}>;
//# sourceMappingURL=fileAdapter.d.ts.map