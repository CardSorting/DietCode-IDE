import { mapRpcError } from '../contracts/errors.js';
function parseCoherenceToken(raw) {
    if (!raw || typeof raw !== 'object')
        return undefined;
    const record = raw;
    const tokenId = typeof record.tokenId === 'string' ? record.tokenId : '';
    if (!tokenId)
        return undefined;
    return {
        tokenId,
        workspaceRevision: Number(record.workspaceRevision ?? 0),
        verifyRevision: Number(record.verifyRevision ?? 0),
        anchors: record.anchors && typeof record.anchors === 'object'
            ? record.anchors
            : {},
    };
}
export async function readFileWithCoherence(transport, path, taskId) {
    const envelope = await transport.call('file.read', { path, taskId });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'readFileWithCoherence');
    }
    const text = typeof envelope.result.text === 'string' ? envelope.result.text : '';
    const coherence = parseCoherenceToken(envelope.result.coherence);
    if (!coherence) {
        throw mapRpcError({
            id: envelope.id,
            ok: false,
            error: {
                code: -32000,
                string_code: 'runtime_unavailable',
                message: 'file.read did not return coherence token for taskId',
            },
        }, 'readFileWithCoherence');
    }
    return { text, coherence };
}
//# sourceMappingURL=fileAdapter.js.map