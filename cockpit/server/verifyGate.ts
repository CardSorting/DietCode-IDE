import { emitBridgeEvent } from './events.js';
import { getTask, listTasks, updateTask } from './taskRegistry.js';
import type { GovernedTask, VerificationState } from './taskRegistry.js';
import { resolveVerifyCommand } from './verifyCommandResolver.js';

export function resolveTaskIdForMutation(explicitTaskId?: string): string | undefined {
  if (explicitTaskId?.trim()) return explicitTaskId.trim();
  const active = listTasks().filter(
    (t) =>
      t.status === 'running' ||
      t.status === 'awaiting_approval' ||
      t.status === 'verification_required',
  );
  if (active.length === 1) return active[0].taskId;
  return undefined;
}

export function noteWorkspaceMutated(
  taskId: string | undefined,
  payload: Record<string, unknown> = {},
): GovernedTask | undefined {
  const resolvedId = resolveTaskIdForMutation(taskId);
  if (!resolvedId) return undefined;

  const task = getTask(resolvedId);
  if (!task) return undefined;

  const incoming = Array.isArray(payload.changedPaths)
    ? (payload.changedPaths as string[]).filter(Boolean)
    : [];
  const mutatedPaths = [...new Set([...(task.mutatedPaths ?? []), ...incoming])];

  const suggestedVerify = resolveVerifyCommand(task.workspace);

  const next = updateTask(resolvedId, {
    verificationState: 'verification_required',
    mutatedPaths,
    mutationCount: (task.mutationCount ?? 0) + 1,
    lastVerifyCommand: task.lastVerifyCommand ?? suggestedVerify,
  });

  if (incoming.length > 0) {
    emitBridgeEvent('workspace.mutated', `Mutated ${incoming.join(', ')}`, {
      taskId: resolvedId,
      changedPaths: incoming,
      method: payload.method ?? 'patch.apply',
    });
  }

  if (next && next.status !== 'verification_required') {
    emitBridgeEvent('task.verification_required', 'Workspace mutated — verification required', {
      taskId: resolvedId,
      changedPaths: incoming,
      mutatedPaths,
    });
  }

  return next;
}

export function finalizeTaskAfterAgentStop(
  taskId: string,
  exitCode: number,
  error?: string,
): GovernedTask | undefined {
  const task = getTask(taskId);
  if (!task) return undefined;

  const needsVerify =
    task.verificationState === 'verification_required' ||
    (task.mutationCount ?? 0) > 0 ||
    (task.mutatedPaths?.length ?? 0) > 0;

  if (needsVerify) {
    const next = updateTask(taskId, {
      status: 'verification_required',
      verificationState: 'verification_required',
      finishedAt: new Date().toISOString(),
      exitCode,
      error: undefined,
    });
    emitBridgeEvent(
      'task.verification_required',
      'Agent stopped — task pending verification',
      { taskId, exitCode },
    );
    return next;
  }

  const next = updateTask(taskId, {
    status: 'completed',
    verificationState: 'none',
    finishedAt: new Date().toISOString(),
    exitCode,
    error: error ?? undefined,
  });
  emitBridgeEvent('task.completed', 'Task completed (no mutations)', { taskId, exitCode });
  return next;
}

function resolveTaskIdForVerify(explicitTaskId?: string): string | undefined {
  if (explicitTaskId?.trim()) return explicitTaskId.trim();
  const pending = listTasks().filter(
    (t) =>
      t.status === 'verification_required' ||
      t.verificationState === 'verification_required' ||
      t.verificationState === 'verification_failed',
  );
  if (pending.length === 1) return pending[0].taskId;
  return undefined;
}

function verifyOutputFromPayload(payload: Record<string, unknown>): string {
  const stdout = String(payload.stdout ?? '');
  const stderr = String(payload.stderr ?? '');
  const combined = [stdout, stderr].filter(Boolean).join('\n');
  return combined.slice(-8000);
}

export function handleVerifyCompleted(
  taskId: string | undefined,
  payload: Record<string, unknown> = {},
): GovernedTask | undefined {
  const resolvedId = resolveTaskIdForVerify(taskId);
  if (!resolvedId) return undefined;

  const task = getTask(resolvedId);
  if (!task) return undefined;

  const passed = payload.passed === true;
  const command = String(payload.command ?? task.lastVerifyCommand ?? '');
  const output = verifyOutputFromPayload(payload);

  if (passed) {
    const next = updateTask(resolvedId, {
      status: 'completed',
      verificationState: 'verified',
      finishedAt: task.finishedAt ?? new Date().toISOString(),
      lastVerifyCommand: command || task.lastVerifyCommand,
      lastVerifyOutput: output,
      error: undefined,
    });
    emitBridgeEvent('task.verified', 'Verification passed — task complete', {
      taskId: resolvedId,
      command,
    });
    emitBridgeEvent('task.completed', 'Task complete after verification', {
      taskId: resolvedId,
      verificationState: 'verified',
    });
    return next;
  }

  const next = updateTask(resolvedId, {
    status: 'verification_failed',
    verificationState: 'verification_failed',
    lastVerifyCommand: command || task.lastVerifyCommand,
    lastVerifyOutput: output,
    error: `Verification failed (exit ${String(payload.exitCode ?? '?')})`,
  });
  emitBridgeEvent('task.verification_failed', 'Verification failed', {
    taskId: resolvedId,
    command,
    exitCode: payload.exitCode,
  });
  return next;
}

export function waiveTaskVerification(taskId: string, reason?: string): GovernedTask | undefined {
  const task = getTask(taskId);
  if (!task) return undefined;
  if (
    task.status !== 'verification_required' &&
    task.status !== 'verification_failed' &&
    task.verificationState !== 'verification_required' &&
    task.verificationState !== 'verification_failed'
  ) {
    return undefined;
  }

  const next = updateTask(taskId, {
    status: 'completed',
    verificationState: 'verification_waived',
    finishedAt: task.finishedAt ?? new Date().toISOString(),
    error: reason ? `Verification waived: ${reason}` : 'Verification waived by operator',
  });
  emitBridgeEvent('task.verification_waived', 'Verification waived — task complete', {
    taskId,
    reason: reason ?? '',
  });
  emitBridgeEvent('task.completed', 'Task complete (verification waived)', {
    taskId,
    verificationState: 'verification_waived',
  });
  return next;
}

export function tasksPendingVerification(): GovernedTask[] {
  return listTasks().filter(
    (t) =>
      t.status === 'verification_required' ||
      t.status === 'verification_failed' ||
      t.verificationState === 'verification_required' ||
      t.verificationState === 'verification_failed',
  );
}

export function isVerificationTerminal(state: VerificationState): boolean {
  return state === 'verified' || state === 'verification_waived';
}
