import type { RpcCaller } from '../client/RpcTransport.js';
import type { MutationReceipt } from '../contracts/types.js';
export interface MutationVerification {
    revisionBefore: number;
    revisionAfter: number;
    revisionBumped: boolean;
    receipt: MutationReceipt;
}
export declare function verifyAfterMutation(transport: RpcCaller, revisionBefore: number, receipt: MutationReceipt): Promise<MutationVerification>;
//# sourceMappingURL=verifyAfterMutation.d.ts.map