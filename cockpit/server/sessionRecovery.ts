import { hydrateEventSequences } from './events.js';
import {
  buildSessionSnapshot,
  initSessionStore,
  setSessionPendingApprovals,
  setSessionTaskCounter,
} from './sessionStore.js';
import { markBridgeRecovered, setSessionAnchorWorkspace } from './healthMonitor.js';
import { restoreTasks, listTasks } from './taskRegistry.js';

type RpcCaller = (method: string, params?: Record<string, unknown>) => Promise<unknown>;

export async function bootstrapSessionRecovery(rpcCall: RpcCaller): Promise<void> {
  const { tasks, events } = await initSessionStore();
  restoreTasks(tasks);

  const hadInterrupted = tasks.some((t) => t.status === 'disconnected');
  markBridgeRecovered(hadInterrupted);

  const anchor = tasks.find((t) => t.workspace)?.workspace;
  setSessionAnchorWorkspace(anchor);

  const meta = {
    bridgeEventSequence: events.reduce(
      (max, event) => (event.sequence >= 1_000_000 ? Math.max(max, event.sequence + 1) : max),
      1_000_000,
    ),
    lastKernelEventSequence: events.reduce(
      (max, event) => (event.source === 'kernel' ? Math.max(max, event.sequence) : max),
      0,
    ),
  };
  hydrateEventSequences(meta);

  const maxTaskNum = tasks.reduce((max, task) => {
    const match = /^task_(\d+)$/.exec(task.taskId);
    return match ? Math.max(max, Number(match[1])) : max;
  }, 0);
  if (maxTaskNum > 0) {
    setSessionTaskCounter(maxTaskNum);
  }

  await syncPendingApprovalsFromKernel(rpcCall);
}

export async function syncPendingApprovalsFromKernel(rpcCall: RpcCaller): Promise<void> {
  try {
    const result = (await rpcCall('approval.list', { status: 'pending', limit: 50 })) as {
      approvals?: Record<string, unknown>[];
    };
    setSessionPendingApprovals(result.approvals ?? []);
  } catch {
    // kernel offline — keep last snapshot
  }
}

export function getSessionState() {
  return buildSessionSnapshot(listTasks());
}
