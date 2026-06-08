import type { GovernedTask } from './taskRegistry.js';
import type { WorkspaceStatus } from './workspaceDrift.js';
import { resolveVerifyCommand } from './verifyCommandResolver.js';

export type CheckpointId = 1 | 2 | 3 | 4 | 5 | 6;

export type CheckpointStatus =
  | 'pending'
  | 'active'
  | 'passed'
  | 'failed'
  | 'blocked'
  | 'waived'
  | 'skipped';

export interface CheckpointState {
  id: CheckpointId;
  key: string;
  name: string;
  question: string;
  status: CheckpointStatus;
  detail?: string;
  blocking?: boolean;
}

export interface TaskCheckpointSnapshot {
  taskId: string;
  taskStatus: string;
  verificationState: string;
  checkpoints: CheckpointState[];
  blockingCheckpoint?: CheckpointId;
  suggestedVerifyCommand?: string;
  canComplete: boolean;
}

function terminalStatuses(): Set<string> {
  return new Set(['completed', 'cancelled', 'failed', 'disconnected']);
}

export function buildTaskCheckpoints(
  task: GovernedTask,
  workspaceStatus?: WorkspaceStatus | null,
  options: {
    driftDetected?: boolean;
    expiredApprovalCount?: number;
  } = {},
): TaskCheckpointSnapshot {
  const drift = options.driftDetected ?? workspaceStatus?.driftDetected === true;
  const mutations = (task.mutationCount ?? 0) > 0 || (task.mutatedPaths?.length ?? 0) > 0;
  const suggestedVerify =
    task.lastVerifyCommand?.trim() ||
    workspaceStatus?.lastVerifiedCommand?.trim() ||
    resolveVerifyCommand(task.workspace);

  const checkpoints: CheckpointState[] = [];

  // 1 · Context
  checkpoints.push({
    id: 1,
    key: 'context',
    name: 'Context',
    question: 'Did the agent read valid state?',
    status:
      task.status === 'queued'
        ? 'pending'
        : drift
          ? 'failed'
          : 'passed',
    detail: drift ? 'Hash anchors stale — refresh context' : undefined,
    blocking: drift,
  });

  // 2 · Drift
  checkpoints.push({
    id: 2,
    key: 'drift',
    name: 'Drift',
    question: 'Did the workspace change underneath it?',
    status: drift ? 'active' : mutations || task.status === 'running' ? 'passed' : 'skipped',
    detail: drift
      ? `${workspaceStatus?.affectedFiles?.length ?? 0} affected file(s)`
      : undefined,
    blocking: drift,
  });

  // 3 · Approval
  const approvalActive = task.status === 'awaiting_approval';
  const approvalExpired = (options.expiredApprovalCount ?? 0) > 0;
  checkpoints.push({
    id: 3,
    key: 'approval',
    name: 'Approval',
    question: 'Is this mutation allowed?',
    status: approvalActive
      ? 'active'
      : approvalExpired
        ? 'blocked'
        : task.mode === 'trusted'
          ? 'skipped'
          : mutations || approvalActive
            ? 'passed'
            : 'pending',
    detail: approvalActive
      ? 'Awaiting cockpit decision'
      : approvalExpired
        ? `${options.expiredApprovalCount} approval(s) expired`
        : undefined,
    blocking: approvalActive || approvalExpired,
  });

  // 4 · Mutation
  checkpoints.push({
    id: 4,
    key: 'mutation',
    name: 'Mutation',
    question: 'Did the patch apply cleanly?',
    status:
      mutations
        ? 'passed'
        : terminalStatuses().has(task.status) && !mutations
          ? 'skipped'
          : task.status === 'running' || task.status === 'awaiting_approval'
            ? 'pending'
            : 'pending',
    detail: mutations ? `${task.mutatedPaths?.length ?? task.mutationCount ?? 0} path(s)` : undefined,
  });

  // 5 · Verification
  const vs = task.verificationState ?? 'none';
  checkpoints.push({
    id: 5,
    key: 'verification',
    name: 'Verification',
    question: 'Did the result pass?',
    status:
      vs === 'verified'
        ? 'passed'
        : vs === 'verification_waived'
          ? 'waived'
          : vs === 'verification_failed' || task.status === 'verification_failed'
            ? 'failed'
            : vs === 'verification_required' || task.status === 'verification_required'
              ? 'active'
              : mutations
                ? 'pending'
                : 'skipped',
    detail:
      vs === 'verification_failed'
        ? task.error ?? 'Verify command failed'
        : vs === 'verification_required'
          ? suggestedVerify
            ? `Run: ${suggestedVerify}`
            : 'No verify command detected'
          : undefined,
    blocking:
      vs === 'verification_required' ||
      vs === 'verification_failed' ||
      task.status === 'verification_required' ||
      task.status === 'verification_failed',
  });

  // 6 · Completion
  const canComplete =
    task.status === 'completed' &&
    (vs === 'verified' || vs === 'verification_waived' || vs === 'none');
  checkpoints.push({
    id: 6,
    key: 'completion',
    name: 'Completion',
    question: 'Can this task be called done?',
    status: canComplete
      ? 'passed'
      : task.status === 'cancelled'
        ? 'skipped'
        : task.status === 'failed' || task.status === 'disconnected'
          ? 'failed'
          : vs === 'verification_required' || task.status === 'verification_required'
            ? 'blocked'
            : task.status === 'running' || task.status === 'awaiting_approval'
              ? 'pending'
              : vs === 'verification_failed'
                ? 'blocked'
                : 'pending',
    detail: canComplete ? 'Task complete' : undefined,
    blocking: !canComplete && !terminalStatuses().has(task.status),
  });

  const blockingCheckpoint = checkpoints.find((c) => c.blocking)?.id;

  return {
    taskId: task.taskId,
    taskStatus: task.status,
    verificationState: vs,
    checkpoints,
    blockingCheckpoint,
    suggestedVerifyCommand: suggestedVerify,
    canComplete,
  };
}

export function buildActiveCheckpointSnapshot(
  tasks: GovernedTask[],
  workspaceStatus?: WorkspaceStatus | null,
  options: { driftDetected?: boolean; expiredApprovalCount?: number } = {},
): TaskCheckpointSnapshot | null {
  const priority = [
    'verification_required',
    'verification_failed',
    'awaiting_approval',
    'running',
    'queued',
    'disconnected',
  ];
  for (const status of priority) {
    const task = tasks.find((t) => t.status === status);
    if (task) return buildTaskCheckpoints(task, workspaceStatus, options);
  }
  const latest = tasks[0];
  return latest ? buildTaskCheckpoints(latest, workspaceStatus, options) : null;
}
