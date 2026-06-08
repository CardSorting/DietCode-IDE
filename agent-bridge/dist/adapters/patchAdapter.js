import { mapRpcError } from '../contracts/errors.js';
import { assertBatchReceipt, assertMutationReceipt, normalizeRpcSuccess, } from '../contracts/schemas.js';
import { validateBatchMutationReceipt, validateMutationReceipt } from '../contracts/validators.js';
export async function validatePatch(transport, path, unifiedDiff) {
    const envelope = await transport.call('patch.validate', { path, patch: unifiedDiff });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'validatePatch');
    }
    const validation = envelope.result.validation;
    return {
        ok: validation.ok === true,
        beforeContentHash: String(validation.beforeContentHash ?? ''),
        patchFingerprint: String(validation.patchFingerprint ?? ''),
        requiresConfirmation: validation.requiresConfirmation === true,
    };
}
export async function applyPatch(transport, path, unifiedDiff, expectBeforeHash, options = {}) {
    const envelope = await transport.call('patch.apply', {
        path,
        patch: unifiedDiff,
        confirm: true,
        dryRun: options.dryRun ?? false,
        expectBeforeHash,
        idempotencyKey: options.idempotencyKey,
    }, { timeoutMs: options.requestTimeoutMs });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'applyPatch');
    }
    const receipt = envelope.result.mutationReceipt;
    if (receipt && typeof receipt === 'object') {
        assertMutationReceipt(receipt);
        const errors = validateMutationReceipt(receipt);
        if (errors.length > 0) {
            throw mapRpcError({ id: envelope.id, ok: false, error: { code: -32000, message: errors.join('; ') } }, 'applyPatch');
        }
    }
    return normalizeRpcSuccess(envelope, options.includeRaw);
}
export async function applyPatchBatch(transport, patches, options = {}) {
    const envelope = await transport.call('patch.applyBatch', {
        patches,
        dryRun: options.dryRun ?? false,
        confirm: options.confirm ?? true,
        idempotencyKey: options.idempotencyKey,
    }, { timeoutMs: options.requestTimeoutMs });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'applyPatchBatch');
    }
    const receipt = envelope.result.batchMutationReceipt;
    if (receipt && typeof receipt === 'object') {
        assertBatchReceipt(receipt);
        const errors = validateBatchMutationReceipt(receipt);
        if (errors.length > 0) {
            throw mapRpcError({ id: envelope.id, ok: false, error: { code: -32000, message: errors.join('; ') } }, 'applyPatchBatch');
        }
    }
    return normalizeRpcSuccess(envelope, options.includeRaw);
}
//# sourceMappingURL=patchAdapter.js.map