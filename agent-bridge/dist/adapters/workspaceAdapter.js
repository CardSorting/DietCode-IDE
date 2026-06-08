import { DietCodeBridgeError } from '../contracts/BridgeError.js';
import { mapRpcError } from '../contracts/errors.js';
export async function getWorkspaceRoot(transport) {
    const envelope = await transport.call('workspace.getRoot', {});
    if (!envelope.ok || !envelope.result) {
        throw mapRpcError(envelope, 'getWorkspaceRoot');
    }
    const path = envelope.result.path;
    return typeof path === 'string' && path.length > 0 ? path : undefined;
}
export async function openWorkspaceFolder(transport, path) {
    const envelope = await transport.call('workspace.openFolder', { path });
    if (!envelope.ok) {
        throw mapRpcError(envelope, 'openWorkspaceFolder');
    }
    const root = await getWorkspaceRoot(transport);
    if (!root) {
        throw new DietCodeBridgeError('runtime_unavailable', `workspace.openFolder succeeded but workspace.getRoot is empty (${path})`);
    }
    return root;
}
export async function ensureWorkspaceRoot(transport, preferredRoot) {
    const existing = await getWorkspaceRoot(transport);
    if (existing) {
        return existing;
    }
    const target = preferredRoot ?? process.env.DIETCODE_TEST_WORKSPACE ?? process.cwd();
    return openWorkspaceFolder(transport, target);
}
//# sourceMappingURL=workspaceAdapter.js.map