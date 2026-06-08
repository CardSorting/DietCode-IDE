import { fetchFileStat } from '../adapters/diagnosticsAdapter.js';
import { resolveBridgeRecovery } from '../contracts/BridgeError.js';
export async function buildStaleRecoveryResponse(transport, path, expectedBeforeHash, idempotencyKey, staleError) {
    let currentContentHash;
    try {
        const stat = await fetchFileStat(transport, path);
        currentContentHash =
            typeof stat.result.contentHash === 'string' ? stat.result.contentHash : undefined;
    }
    catch {
        currentContentHash = undefined;
    }
    const resolved = resolveBridgeRecovery('stale_content', staleError, {
        recoveryHint: typeof staleError?.recovery_hint === 'string' ? staleError.recovery_hint : undefined,
        nextRecommendedCommand: typeof staleError?.nextRecommendedCommand === 'string'
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
//# sourceMappingURL=stalePatchRecovery.js.map