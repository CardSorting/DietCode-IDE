import { bridgeError } from '../contracts/errors.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type { RpcEnvelope } from '../contracts/types.js';

const POLL_MS = 2000;
const DEFAULT_TIMEOUT_MS = 30 * 60 * 1000;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function waitForWorkspaceContextRefresh(
  transport: RpcCaller,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<number> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const envelope = await transport.call('workspace.status', {});
    if (!envelope.ok || !envelope.result) {
      throw bridgeError('workspace_drift', 'workspace.status failed while waiting for refresh');
    }
    const status = envelope.result as Record<string, unknown>;
    if (status.driftDetected !== true) {
      return Number(status.contextRefreshId ?? 0);
    }
    await sleep(POLL_MS);
  }
  throw bridgeError('workspace_drift', 'Timed out waiting for workspace context refresh');
}

export async function completeAfterWorkspaceRefresh(
  transport: RpcCaller,
  driftResult: Record<string, unknown>,
  method: string,
  params: Record<string, unknown>,
  options: { timeoutMs?: number } = {},
): Promise<RpcEnvelope> {
  const workspace = driftResult.workspace as Record<string, unknown> | undefined;
  if (!workspace) {
    throw bridgeError('workspace_drift', 'workspaceDriftRequired response missing workspace status');
  }

  const contextRefreshId = await waitForWorkspaceContextRefresh(
    transport,
    options.timeoutMs ?? DEFAULT_TIMEOUT_MS,
  );

  return transport.call(method, {
    ...params,
    contextRefreshId,
  });
}
