import { mapRpcError } from '../contracts/errors.js';
import { normalizeRpcSuccess } from '../contracts/schemas.js';
export async function fetchDiagnostics(transport, includeRaw = false) {
    const envelope = await transport.call('runtime.diagnostics', {});
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'getDiagnostics');
    }
    return normalizeRpcSuccess(envelope, includeRaw);
}
export async function fetchFileStat(transport, path, includeRaw = false) {
    const envelope = await transport.call('file.stat', { path });
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'getFileStat');
    }
    return normalizeRpcSuccess(envelope, includeRaw);
}
//# sourceMappingURL=diagnosticsAdapter.js.map