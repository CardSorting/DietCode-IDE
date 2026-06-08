import { fetchFileStat } from '../adapters/diagnosticsAdapter.js';
export async function buildStaleRecoveryResponse(transport, path, expectedBeforeHash, idempotencyKey) {
    let currentContentHash;
    try {
        const stat = await fetchFileStat(transport, path);
        currentContentHash =
            typeof stat.result.contentHash === 'string' ? stat.result.contentHash : undefined;
    }
    catch {
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
//# sourceMappingURL=stalePatchRecovery.js.map