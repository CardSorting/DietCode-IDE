import { fetchWorkspaceRevision } from '../adapters/runtimeAdapter.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type { MutationReceipt } from '../contracts/types.js';

export interface MutationVerification {
  revisionBefore: number;
  revisionAfter: number;
  revisionBumped: boolean;
  receipt: MutationReceipt;
}

export async function verifyAfterMutation(
  transport: RpcCaller,
  revisionBefore: number,
  receipt: MutationReceipt,
): Promise<MutationVerification> {
  const revisionAfter = await fetchWorkspaceRevision(transport);
  return {
    revisionBefore,
    revisionAfter,
    revisionBumped: revisionAfter > revisionBefore,
    receipt,
  };
}
