import { mapRpcError } from '../contracts/errors.js';
import { normalizeRpcSuccess } from '../contracts/schemas.js';
async function callShell(transport, method, params, label) {
    const envelope = await transport.call(method, params);
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, label);
    }
    return normalizeRpcSuccess(envelope);
}
export async function shellPwd(transport) {
    return callShell(transport, 'shell.pwd', {}, 'shellPwd');
}
export async function shellCd(transport, path) {
    return callShell(transport, 'shell.cd', { path }, 'shellCd');
}
export async function shellRg(transport, pattern, options = {}) {
    return callShell(transport, 'shell.rg', {
        pattern,
        ...options,
    }, 'shellRg');
}
export async function shellHead(transport, path, lines) {
    return callShell(transport, 'shell.head', { path, ...(lines ? { lines } : {}) }, 'shellHead');
}
export async function shellTail(transport, path, lines) {
    return callShell(transport, 'shell.tail', { path, ...(lines ? { lines } : {}) }, 'shellTail');
}
export async function shellSedRange(transport, path, startLine, endLine) {
    return callShell(transport, 'shell.sedRange', { path, startLine, endLine }, 'shellSedRange');
}
export async function shellCatSmall(transport, path) {
    return callShell(transport, 'shell.catSmall', { path }, 'shellCatSmall');
}
//# sourceMappingURL=shellAdapter.js.map