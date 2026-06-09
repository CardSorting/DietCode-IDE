import { bridgeError } from '../contracts/errors.js';
const POLL_MS = 2000;
const DEFAULT_TIMEOUT_MS = 30 * 60 * 1000;
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
export async function waitForWorkspaceContextRefresh(transport, timeoutMs = DEFAULT_TIMEOUT_MS) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        const envelope = await transport.call('workspace.status', {});
        if (!envelope.ok || !envelope.result) {
            throw bridgeError('workspace_drift', 'workspace.status failed while waiting for refresh');
        }
        const status = envelope.result;
        if (status.driftDetected !== true) {
            return Number(status.contextRefreshId ?? 0);
        }
        await sleep(POLL_MS);
    }
    throw bridgeError('workspace_drift', 'Timed out waiting for workspace context refresh');
}
function isHeadlessAutoResolve() {
    return process.env.DIETCODE_HEADLESS_AUTO_APPROVE === '1';
}
async function refreshWorkspaceAnchor(transport) {
    const envelope = await transport.call('workspace.refreshAnchor', {});
    if (!envelope.ok || !envelope.result) {
        throw bridgeError('workspace_drift', 'workspace.refreshAnchor failed during headless recovery');
    }
    const status = envelope.result;
    return Number(status.contextRefreshId ?? 0);
}
export async function completeAfterWorkspaceRefresh(transport, driftResult, method, params, options = {}) {
    const workspace = driftResult.workspace;
    if (!workspace) {
        throw bridgeError('workspace_drift', 'workspaceDriftRequired response missing workspace status');
    }
    const contextRefreshId = isHeadlessAutoResolve()
        ? await refreshWorkspaceAnchor(transport)
        : await waitForWorkspaceContextRefresh(transport, options.timeoutMs ?? DEFAULT_TIMEOUT_MS);
    return transport.call(method, {
        ...params,
        contextRefreshId,
    });
}
//# sourceMappingURL=awaitWorkspaceDrift.js.map