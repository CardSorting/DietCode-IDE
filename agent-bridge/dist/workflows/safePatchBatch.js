import { randomUUID } from 'node:crypto';
import { applyPatchBatch, validatePatch } from '../adapters/patchAdapter.js';
import { readFileWithCoherence } from '../adapters/fileAdapter.js';
import { fetchFileStat } from '../adapters/diagnosticsAdapter.js';
import { fetchOperationStatus, fetchWorkspaceRevision } from '../adapters/runtimeAdapter.js';
import { isBridgeError } from '../contracts/BridgeError.js';
import { resolveBridgeRecovery } from '../contracts/BridgeError.js';
import { createTaskCoherenceLogger } from '../telemetry/coherenceEvents.js';
import { parseCoherenceMismatch } from './coherenceRecovery.js';
function resolveBatchOptions(options) {
    const taskId = options.taskId ?? (process.env.DIETCODE_TASK_ID?.trim() || undefined);
    const onCoherenceEvent = options.onCoherenceEvent ?? createTaskCoherenceLogger();
    return { ...options, taskId, onCoherenceEvent };
}
async function resolveCoherenceForBatch(transport, paths, options) {
    if (!options.taskId) {
        return {};
    }
    if (options.coherenceTokenId && options.expectedWorkspaceRevision != null) {
        return {
            coherenceTokenId: options.coherenceTokenId,
            expectedWorkspaceRevision: options.expectedWorkspaceRevision,
        };
    }
    let latest;
    for (const relPath of paths) {
        const read = await readFileWithCoherence(transport, relPath, options.taskId);
        latest = {
            tokenId: read.coherence.tokenId,
            workspaceRevision: read.coherence.workspaceRevision,
        };
    }
    return latest
        ? {
            coherenceTokenId: latest.tokenId,
            expectedWorkspaceRevision: latest.workspaceRevision,
        }
        : {};
}
export async function safePatchBatch(transport, patches, options = {}) {
    const resolved = resolveBatchOptions(options);
    const idempotencyKey = resolved.idempotencyKey ?? `bridge-batch:${randomUUID()}`;
    const emit = resolved.onCoherenceEvent;
    const rpcPatches = [];
    const hashesBefore = new Map();
    for (const entry of patches) {
        const validation = await validatePatch(transport, entry.path, entry.unifiedDiff);
        if (!validation.ok) {
            return {
                applied: false,
                atomic: true,
                rolledBack: true,
                failedPath: entry.path,
                idempotencyKey,
                recoveryHint: 'run_patch_preview_or_patch_validate',
                nextRecommendedCommand: 'patch.validate',
                filesVerifiedUnchanged: true,
            };
        }
        rpcPatches.push({
            path: entry.path,
            patch: entry.unifiedDiff,
            expectBeforeHash: validation.beforeContentHash,
        });
        hashesBefore.set(entry.path, validation.beforeContentHash);
    }
    const revisionBefore = await fetchWorkspaceRevision(transport);
    const uniquePaths = [...new Set(patches.map((entry) => entry.path))];
    const coherenceFields = await resolveCoherenceForBatch(transport, uniquePaths, resolved);
    try {
        const applied = await applyPatchBatch(transport, rpcPatches, {
            ...resolved,
            ...coherenceFields,
            idempotencyKey,
        });
        const receipt = applied.result.batchMutationReceipt;
        const revisionAfter = await fetchWorkspaceRevision(transport);
        return {
            applied: true,
            atomic: true,
            batchMutationReceipt: receipt,
            idempotencyKey,
            revisionBefore,
            revisionAfter,
            nextRecommendedCommand: applied.nextRecommendedCommand ?? 'workspace.revision',
        };
    }
    catch (error) {
        if (isBridgeError(error) && error.code === 'nested_call_timeout') {
            const status = await fetchOperationStatus(transport, idempotencyKey);
            if (status.status === 'completed' && status.batchMutationReceipt) {
                return {
                    applied: true,
                    atomic: true,
                    batchMutationReceipt: status.batchMutationReceipt,
                    idempotencyKey,
                    revisionBefore: status.revisionBefore,
                    revisionAfter: status.revisionAfter,
                    nextRecommendedCommand: 'workspace.revision',
                };
            }
            throw error;
        }
        const filesVerifiedUnchanged = await verifyFilesUnchanged(transport, hashesBefore);
        const failedPath = isBridgeError(error) ? inferFailedPath(error, rpcPatches) : rpcPatches[0]?.path;
        if (isBridgeError(error) && error.code === 'coherence_mismatch') {
            const detail = parseCoherenceMismatch(error.rawError);
            const stalePath = failedPath ?? rpcPatches[0]?.path ?? '';
            emit?.({
                type: 'context.stale',
                path: stalePath,
                taskId: resolved.taskId,
                reason: detail.reason,
                changedPaths: detail.changedPaths,
            });
            const recovery = resolveBridgeRecovery('coherence_mismatch', error.rawError, { retrySafe: true });
            return {
                applied: false,
                atomic: true,
                rolledBack: true,
                failedPath,
                idempotencyKey,
                recoveryHint: recovery.recoveryHint,
                nextRecommendedCommand: recovery.nextRecommendedCommand,
                filesVerifiedUnchanged,
                coherenceStale: true,
                reason: detail.reason,
                changedPaths: detail.changedPaths,
            };
        }
        return {
            applied: false,
            atomic: true,
            rolledBack: true,
            failedPath,
            idempotencyKey,
            recoveryHint: isBridgeError(error)
                ? error.code === 'stale_content'
                    ? 'revalidate_patch_with_patch.validate'
                    : error.recoveryHint
                : 'revalidate_batch_with_patch.validate',
            nextRecommendedCommand: isBridgeError(error)
                ? error.nextRecommendedCommand
                : 'patch.validate',
            filesVerifiedUnchanged,
            ...(isBridgeError(error) && error.code === 'stale_content' ? { stale: true } : {}),
        };
    }
}
function inferFailedPath(error, patches) {
    if (error.rawError?.path) {
        return String(error.rawError.path);
    }
    return patches[0]?.path;
}
async function verifyFilesUnchanged(transport, hashesBefore) {
    for (const [path, beforeHash] of hashesBefore) {
        try {
            const stat = await fetchFileStat(transport, path);
            const current = String(stat.result.contentHash ?? '');
            if (current !== beforeHash) {
                return false;
            }
        }
        catch {
            return false;
        }
    }
    return true;
}
//# sourceMappingURL=safePatchBatch.js.map