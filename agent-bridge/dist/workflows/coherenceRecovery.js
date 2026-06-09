import { resolveBridgeRecovery } from '../contracts/BridgeError.js';
import { readFileWithCoherence } from '../adapters/fileAdapter.js';
export function parseCoherenceMismatch(rawError) {
    const coherence = rawError?.coherence && typeof rawError.coherence === 'object'
        ? rawError.coherence
        : undefined;
    const changedPathsRaw = rawError?.changedPaths ?? coherence?.changedPaths;
    const changedPaths = Array.isArray(changedPathsRaw)
        ? changedPathsRaw.filter((p) => typeof p === 'string' && p.length > 0)
        : [];
    const reason = (typeof rawError?.reason === 'string' && rawError.reason) ||
        (typeof coherence?.reason === 'string' && coherence.reason) ||
        'unknown';
    return {
        reason,
        changedPaths,
        requiredAction: typeof rawError?.requiredAction === 'string'
            ? rawError.requiredAction
            : typeof coherence?.requiredAction === 'string'
                ? coherence.requiredAction
                : undefined,
        currentWorkspaceRevision: typeof rawError?.currentWorkspaceRevision === 'number'
            ? rawError.currentWorkspaceRevision
            : typeof coherence?.currentWorkspaceRevision === 'number'
                ? coherence.currentWorkspaceRevision
                : undefined,
    };
}
export function buildCoherenceStaleRecovery(path, idempotencyKey, detail, rawError) {
    const resolved = resolveBridgeRecovery('coherence_mismatch', rawError, { retrySafe: true });
    return {
        applied: false,
        coherenceStale: true,
        operatorInterventionRequired: false,
        path,
        reason: detail.reason,
        changedPaths: detail.changedPaths,
        recoveryHint: resolved.recoveryHint,
        nextRecommendedCommand: resolved.nextRecommendedCommand,
        recoverySource: resolved.recoverySource,
        nextCommandSource: resolved.nextCommandSource,
        idempotencyKey,
    };
}
export function buildCoherenceOperatorRequired(path, idempotencyKey, detail, rawError) {
    const resolved = resolveBridgeRecovery('coherence_mismatch', rawError, { retrySafe: false });
    return {
        applied: false,
        coherenceStale: true,
        operatorInterventionRequired: true,
        path,
        reason: detail.reason,
        changedPaths: detail.changedPaths,
        recoveryHint: resolved.recoveryHint,
        nextRecommendedCommand: resolved.nextRecommendedCommand,
        recoverySource: resolved.recoverySource,
        nextCommandSource: resolved.nextCommandSource,
        idempotencyKey,
    };
}
export async function refreshCoherenceContext(transport, taskId, paths, emit) {
    const primary = paths[0];
    if (!primary) {
        throw new Error('refreshCoherenceContext requires at least one path');
    }
    let latest;
    for (const relPath of paths) {
        const read = await readFileWithCoherence(transport, relPath, taskId);
        latest = { path: relPath, text: read.text, coherence: read.coherence };
        emit?.({
            type: 'context.refreshed',
            path: relPath,
            taskId,
            tokenId: read.coherence.tokenId,
        });
    }
    if (!latest) {
        const read = await readFileWithCoherence(transport, primary, taskId);
        latest = { path: primary, text: read.text, coherence: read.coherence };
    }
    return latest;
}
//# sourceMappingURL=coherenceRecovery.js.map