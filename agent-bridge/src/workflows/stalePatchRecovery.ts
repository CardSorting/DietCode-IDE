import { fetchFileStat } from '../adapters/diagnosticsAdapter.js';
import { resolveBridgeRecovery } from '../contracts/BridgeError.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type { StalePatchRecovery } from '../contracts/types.js';

export async function buildStaleRecoveryResponse(
  transport: RpcCaller,
  path: string,
  expectedBeforeHash: string,
  idempotencyKey: string,
  staleError?: Record<string, unknown>,
): Promise<StalePatchRecovery> {
  let currentContentHash: string | undefined;
  try {
    const stat = await fetchFileStat(transport, path);
    currentContentHash =
      typeof stat.result.contentHash === 'string' ? stat.result.contentHash : undefined;
  } catch {
    currentContentHash = undefined;
  }

  const resolved = resolveBridgeRecovery('stale_content', staleError, {
    recoveryHint:
      typeof staleError?.recovery_hint === 'string' ? staleError.recovery_hint : undefined,
    nextRecommendedCommand:
      typeof staleError?.nextRecommendedCommand === 'string'
        ? staleError.nextRecommendedCommand
        : undefined,
    retrySafe: false,
  });

  return {
    applied: false,
    stale: true,
    path,
    expectedBeforeHash,
    currentContentHash,
    recoveryHint: resolved.recoveryHint,
    nextRecommendedCommand: resolved.nextRecommendedCommand,
    recoverySource: resolved.recoverySource,
    nextCommandSource: resolved.nextCommandSource,
    idempotencyKey,
  };
}
