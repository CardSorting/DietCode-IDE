import { fetchFileStat } from '../adapters/diagnosticsAdapter.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type { StalePatchRecovery } from '../contracts/types.js';

export async function buildStaleRecoveryResponse(
  transport: RpcCaller,
  path: string,
  expectedBeforeHash: string,
  idempotencyKey: string,
): Promise<StalePatchRecovery> {
  let currentContentHash: string | undefined;
  try {
    const stat = await fetchFileStat(transport, path);
    currentContentHash =
      typeof stat.result.contentHash === 'string' ? stat.result.contentHash : undefined;
  } catch {
    currentContentHash = undefined;
  }

  return {
    applied: false,
    stale: true,
    path,
    expectedBeforeHash,
    currentContentHash,
    recoveryHint: 'revalidate_patch_with_patch.validate',
    nextRecommendedCommand: 'patch.validate',
    idempotencyKey,
  };
}
