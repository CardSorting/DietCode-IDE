import { randomUUID } from 'node:crypto';
import { applyPatch, validatePatch } from '../adapters/patchAdapter.js';
import { fetchOperationStatus, fetchWorkspaceRevision } from '../adapters/runtimeAdapter.js';
import { isBridgeError } from '../contracts/BridgeError.js';
import { bridgeError } from '../contracts/errors.js';
import { recordMutationPatchApplied } from '../telemetry/mutationTelemetry.js';
import { buildStaleRecoveryResponse } from './stalePatchRecovery.js';
import { verifyAfterMutation } from './verifyAfterMutation.js';
export async function safePatchFile(transport, path, unifiedDiff, options = {}) {
    const idempotencyKey = options.idempotencyKey ?? `bridge-patch:${randomUUID()}`;
    const validation = await validatePatch(transport, path, unifiedDiff);
    if (!validation.ok) {
        throw bridgeError('patch_failed', 'patch validation failed before apply');
    }
    const liveBeforeHash = validation.beforeContentHash;
    const revisionBefore = await fetchWorkspaceRevision(transport);
    try {
        const applied = await applyPatch(transport, path, unifiedDiff, liveBeforeHash, {
            ...options,
            idempotencyKey,
        });
        const receipt = applied.result.mutationReceipt;
        const verified = await verifyAfterMutation(transport, revisionBefore, receipt);
        recordMutationPatchApplied({
            workspace: process.env.DIETCODE_WORKSPACE ?? process.env.HERMES_KANBAN_WORKSPACE ?? '',
            path: receipt.path,
            beforeHash: receipt.beforeContentHash,
            afterHash: receipt.postContentHash,
            tool: 'dietcode_ide.patch',
            protocol: 'safePatchFile',
            idempotencyKey,
        });
        return {
            applied: true,
            mutationReceipt: receipt,
            revisionBefore: verified.revisionBefore,
            revisionAfter: verified.revisionAfter,
            idempotencyKey,
            nextRecommendedCommand: applied.nextRecommendedCommand ?? 'workspace.revision',
            beforeHashSource: 'live_validate',
            beforeContentHash: liveBeforeHash,
        };
    }
    catch (error) {
        if (isBridgeError(error) && error.code === 'stale_content') {
            return buildStaleRecoveryResponse(transport, path, liveBeforeHash, idempotencyKey, error.rawError);
        }
        if (isBridgeError(error) && error.code === 'nested_call_timeout') {
            const status = await fetchOperationStatus(transport, idempotencyKey);
            if (status.status === 'completed' && status.mutationReceipt) {
                return {
                    applied: true,
                    mutationReceipt: status.mutationReceipt,
                    revisionBefore: status.revisionBefore,
                    revisionAfter: status.revisionAfter,
                    idempotencyKey,
                    nextRecommendedCommand: 'workspace.revision',
                    beforeHashSource: 'live_validate',
                    beforeContentHash: liveBeforeHash,
                };
            }
            throw error;
        }
        throw error;
    }
}
//# sourceMappingURL=safePatchFile.js.map