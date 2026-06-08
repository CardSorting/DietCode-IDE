import { mapRpcError } from '../contracts/errors.js';
import { normalizeRpcSuccess } from '../contracts/schemas.js';
const JOURNAL_AUTHORITY = {
    recordAuthority: 'runtime_journal',
    mutationAuthority: 'cpp_kernel',
    currentStateAuthority: 'workspace_live_read',
    notCurrentFileTruth: true,
};
export function applyJournalAuthorityLabels(raw) {
    return {
        ...raw,
        ...JOURNAL_AUTHORITY,
    };
}
export async function fetchTimeline(transport, options = {}) {
    const envelope = await transport.call('runtime.timeline', {
        limit: options.limit ?? 20,
        offset: options.offset ?? 0,
        sinceRevision: options.sinceRevision,
        errorsOnly: options.errorsOnly ?? false,
    });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'getTimeline');
    }
    const normalized = normalizeRpcSuccess(envelope, options.includeRaw);
    return {
        ...normalized,
        result: applyJournalAuthorityLabels(normalized.result),
    };
}
export async function fetchRecentActivity(transport, options = {}) {
    const envelope = await transport.call('workspace.activity', {
        limit: options.limit ?? 20,
        sinceRevision: options.sinceRevision,
    });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'getRecentActivity');
    }
    const normalized = normalizeRpcSuccess(envelope, options.includeRaw);
    return {
        ...normalized,
        result: applyJournalAuthorityLabels(normalized.result),
    };
}
export async function fetchOperationStatus(transport, idempotencyKey) {
    const envelope = await transport.call('operation.status', { idempotencyKey });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'getOperationStatus');
    }
    const raw = applyJournalAuthorityLabels(envelope.result);
    return {
        status: raw.status ?? 'unknown',
        idempotencyKey,
        revisionBefore: typeof raw.revisionBefore === 'number' ? raw.revisionBefore : undefined,
        revisionAfter: typeof raw.revisionAfter === 'number' ? raw.revisionAfter : undefined,
        changedFiles: Array.isArray(raw.changedFiles)
            ? raw.changedFiles.filter((p) => typeof p === 'string')
            : undefined,
        mutationReceipt: raw.mutationReceipt,
        batchMutationReceipt: raw.batchMutationReceipt,
        completedAt: typeof raw.completedAt === 'string' ? raw.completedAt : undefined,
        recordAuthority: raw.recordAuthority,
        mutationAuthority: raw.mutationAuthority,
        currentStateAuthority: raw.currentStateAuthority,
        notCurrentFileTruth: raw.notCurrentFileTruth,
    };
}
export async function verifyFast(transport) {
    const started = performance.now();
    const ping = await transport.call('rpc.ping', {}, { timeoutMs: 5_000 });
    const rpcReady = ping.ok === true;
    let runtimeAvailable = false;
    if (rpcReady) {
        const diagnostics = await transport.call('runtime.diagnostics', {}, { timeoutMs: 5_000 });
        runtimeAvailable = diagnostics.ok === true && diagnostics.result?.available === true;
    }
    return {
        ok: rpcReady && runtimeAvailable,
        rpcReady,
        runtimeAvailable,
        latencyMs: Math.round(performance.now() - started),
    };
}
export async function fetchWorkspaceRevision(transport) {
    const envelope = await transport.call('workspace.revision', {});
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'workspace.revision');
    }
    return Number(envelope.result.revisionId ?? 0);
}
//# sourceMappingURL=runtimeAdapter.js.map