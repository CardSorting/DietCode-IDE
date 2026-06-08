import { randomUUID } from 'node:crypto';
import { applyPatch, validatePatch } from '../adapters/patchAdapter.js';
import { fetchOperationStatus, fetchWorkspaceRevision } from '../adapters/runtimeAdapter.js';
import { isBridgeError } from '../contracts/BridgeError.js';
import { bridgeError } from '../contracts/errors.js';
import { buildStaleRecoveryResponse } from './stalePatchRecovery.js';
import { verifyAfterMutation } from './verifyAfterMutation.js';
export async function safePatchFile(transport, path, unifiedDiff, options = {}) {
    const idempotencyKey = options.idempotencyKey ?? `bridge-patch:${randomUUID()}`;
    const validation = await validatePatch(transport, path, unifiedDiff);
    if (!validation.ok) {
        throw bridgeError('patch_failed', 'patch validation failed before apply');
    }
    const revisionBefore = await fetchWorkspaceRevision(transport);
    try {
        const applied = await applyPatch(transport, path, unifiedDiff, validation.beforeContentHash, {
            ...options,
            idempotencyKey,
        });
        const receipt = applied.result.mutationReceipt;
        const verified = await verifyAfterMutation(transport, revisionBefore, receipt);
        return {
            applied: true,
            mutationReceipt: receipt,
            revisionBefore: verified.revisionBefore,
            revisionAfter: verified.revisionAfter,
            idempotencyKey,
            nextRecommendedCommand: applied.nextRecommendedCommand ?? 'workspace.revision',
        };
    }
    catch (error) {
        if (isBridgeError(error) && error.code === 'stale_content') {
            return buildStaleRecoveryResponse(transport, path, validation.beforeContentHash, idempotencyKey);
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
                };
            }
            throw error;
        }
        throw error;
    }
}
//# sourceMappingURL=safePatchFile.js.map