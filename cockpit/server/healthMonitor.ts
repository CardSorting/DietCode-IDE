import type { GovernedTask } from './taskRegistry.js';
import { getSessionPendingApprovals } from './sessionStore.js';
import {
  fetchWorkspaceStatus,
  formatAffectedFileLine,
  getCachedWorkspaceStatus,
  type AffectedFile,
  type WorkspaceStatus,
} from './workspaceDrift.js';

export interface HealthBanner {
  id: string;
  severity: 'info' | 'warning' | 'error';
  message: string;
  detail?: string;
}

export interface HealthSnapshot {
  kernelConnected: boolean;
  kernelError?: string;
  kernelLastSeenAt?: string;
  bridgeRecovered: boolean;
  workspacePath?: string;
  workspaceDrift: boolean;
  externalChangeDetected: boolean;
  workspaceStatus?: WorkspaceStatus;
  affectedFiles?: AffectedFile[];
  expiredApprovalCount: number;
  expiredApprovalIds: string[];
  banners: HealthBanner[];
  tasks: {
    disconnected: string[];
    awaitingApproval: string[];
    running: string[];
    queued: string[];
  };
}

let kernelConnected = false;
let kernelError: string | undefined;
let kernelLastSeenAt: string | undefined;
let bridgeRecovered = false;
let bridgeRecoveredAt: string | undefined;
let workspacePath: string | undefined;
let sessionAnchorWorkspace: string | undefined;
let externalChangeDetected = false;
let expiredApprovalIds: string[] = [];

export function markBridgeRecovered(hadInterruptedTasks: boolean): void {
  if (hadInterruptedTasks) {
    bridgeRecovered = true;
    bridgeRecoveredAt = new Date().toISOString();
  }
}

export function dismissBridgeRecovered(): void {
  bridgeRecovered = false;
  bridgeRecoveredAt = undefined;
}

export function setSessionAnchorWorkspace(path: string | undefined): void {
  if (path) sessionAnchorWorkspace = path;
}

export function noteKernelSuccess(rootPath?: string): void {
  kernelConnected = true;
  kernelError = undefined;
  kernelLastSeenAt = new Date().toISOString();
  if (rootPath) workspacePath = rootPath;
}

export function noteKernelFailure(error: string): void {
  kernelConnected = false;
  kernelError = error;
}

export async function probeKernel(
  rpcCall: (method: string, params?: Record<string, unknown>) => Promise<unknown>,
): Promise<void> {
  try {
    await rpcCall('rpc.ping');
    const root = (await rpcCall('workspace.getRoot')) as { path?: string };
    const revision = (await rpcCall('workspace.revision')) as {
      externalChangeDetected?: boolean;
    };
    externalChangeDetected = revision.externalChangeDetected === true;
    await fetchWorkspaceStatus(rpcCall);
    const status = getCachedWorkspaceStatus();
    if (status?.externalChangeDetected) {
      externalChangeDetected = true;
    }
    noteKernelSuccess(root.path);
  } catch (err) {
    noteKernelFailure(String(err));
  }
}

export async function refreshExpiredApprovals(
  rpcCall: (method: string, params?: Record<string, unknown>) => Promise<unknown>,
): Promise<string[]> {
  try {
    const result = (await rpcCall('approval.list', { status: 'expired', limit: 50 })) as {
      approvals?: Array<{ approvalId?: string }>;
    };
    expiredApprovalIds = (result.approvals ?? [])
      .map((a) => a.approvalId)
      .filter((id): id is string => typeof id === 'string');
  } catch {
    expiredApprovalIds = getSessionPendingApprovals()
      .filter((a) => a.status === 'expired')
      .map((a) => String(a.approvalId ?? ''))
      .filter(Boolean);
  }
  return expiredApprovalIds;
}

function workspaceDrifted(): boolean {
  if (!sessionAnchorWorkspace || !workspacePath) return false;
  return sessionAnchorWorkspace !== workspacePath;
}

export function buildHealthSnapshot(tasks: GovernedTask[]): HealthSnapshot {
  const disconnected = tasks.filter((t) => t.status === 'disconnected').map((t) => t.taskId);
  const awaitingApproval = tasks
    .filter((t) => t.status === 'awaiting_approval')
    .map((t) => t.taskId);
  const running = tasks.filter((t) => t.status === 'running').map((t) => t.taskId);
  const queued = tasks.filter((t) => t.status === 'queued').map((t) => t.taskId);

  const banners: HealthBanner[] = [];

  if (!kernelConnected) {
    banners.push({
      id: 'kernel_offline',
      severity: 'error',
      message: 'Kernel offline',
      detail: kernelError ?? 'Cannot reach dietcode-kernel control socket.',
    });
  }

  if (bridgeRecovered) {
    banners.push({
      id: 'bridge_reconnected',
      severity: 'warning',
      message: 'Bridge reconnected',
      detail: 'Session restored. Tasks that were running may be disconnected.',
    });
  }

  for (const taskId of disconnected) {
    const task = tasks.find((t) => t.taskId === taskId);
    banners.push({
      id: `task_disconnected_${taskId}`,
      severity: 'error',
      message: 'Task disconnected',
      detail: task?.error ?? `${taskId} lost its agent process or bridge restarted mid-run.`,
    });
  }

  if (expiredApprovalIds.length > 0) {
    banners.push({
      id: 'approval_expired',
      severity: 'warning',
      message: 'Approval expired',
      detail: `${expiredApprovalIds.length} approval(s) expired without a decision.`,
    });
  }

  const workspaceStatus = getCachedWorkspaceStatus() ?? undefined;
  const affectedFiles = workspaceStatus?.affectedFiles ?? [];
  const kernelDrift = workspaceStatus?.driftDetected === true;
  const pathDrift = workspaceDrifted();

  if (kernelDrift || externalChangeDetected || pathDrift) {
    const fileSummary =
      affectedFiles.length > 0
        ? affectedFiles.slice(0, 4).map(formatAffectedFileLine).join('; ')
        : pathDrift
          ? `Session anchor ${sessionAnchorWorkspace} ≠ kernel root ${workspacePath}`
          : 'Kernel detected filesystem changes outside DietCode RPC.';
    banners.push({
      id: 'workspace_drift',
      severity: 'warning',
      message: 'Workspace changed outside DietCode',
      detail: fileSummary,
    });
  }

  return {
    kernelConnected,
    kernelError,
    kernelLastSeenAt,
    bridgeRecovered,
    workspacePath,
    workspaceDrift: pathDrift || kernelDrift,
    externalChangeDetected,
    workspaceStatus,
    affectedFiles,
    expiredApprovalCount: expiredApprovalIds.length,
    expiredApprovalIds,
    banners,
    tasks: { disconnected, awaitingApproval, running, queued },
  };
}
