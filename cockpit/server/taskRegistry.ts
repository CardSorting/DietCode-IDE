import { nextSessionTaskId, persistActiveTasks } from './sessionStore.js';

export type TaskMode = 'supervised' | 'trusted';

export type VerificationState =
  | 'none'
  | 'verification_required'
  | 'verified'
  | 'verification_failed'
  | 'verification_waived';

export type TaskStatus =
  | 'queued'
  | 'running'
  | 'awaiting_approval'
  | 'verification_required'
  | 'verification_failed'
  | 'disconnected'
  | 'failed'
  | 'completed'
  | 'cancelled';

/** @deprecated use queued */
export type LegacyTaskStatus = 'pending';

export interface GovernedTask {
  taskId: string;
  message: string;
  workspace: string;
  mode: TaskMode;
  status: TaskStatus;
  verificationState: VerificationState;
  createdAt: string;
  startedAt?: string;
  finishedAt?: string;
  exitCode?: number;
  error?: string;
  mutationCount?: number;
  mutatedPaths?: string[];
  lastVerifyCommand?: string;
  lastVerifyOutput?: string;
}

const tasks = new Map<string, GovernedTask>();
const MAX_TASKS = 40;

function persistTasks(): void {
  void persistActiveTasks(listTasks(MAX_TASKS));
}

export function normalizeVerificationState(state: string | undefined): VerificationState {
  if (
    state === 'verification_required' ||
    state === 'verified' ||
    state === 'verification_failed' ||
    state === 'verification_waived'
  ) {
    return state;
  }
  return 'none';
}

export function normalizeTaskStatus(status: string): TaskStatus {
  if (status === 'pending') return 'queued';
  if (
    status === 'queued' ||
    status === 'running' ||
    status === 'awaiting_approval' ||
    status === 'verification_required' ||
    status === 'verification_failed' ||
    status === 'disconnected' ||
    status === 'failed' ||
    status === 'completed' ||
    status === 'cancelled'
  ) {
    return status;
  }
  return 'failed';
}

export function nextTaskId(): string {
  return nextSessionTaskId();
}

export function restoreTasks(restored: GovernedTask[]): void {
  tasks.clear();
  for (const task of restored) {
    tasks.set(task.taskId, {
      ...task,
      status: normalizeTaskStatus(task.status),
      verificationState: normalizeVerificationState(task.verificationState),
    });
  }
}

export function createTask(input: {
  message: string;
  workspace: string;
  mode: TaskMode;
}): GovernedTask {
  const task: GovernedTask = {
    taskId: nextTaskId(),
    message: input.message,
    workspace: input.workspace,
    mode: input.mode,
    status: 'queued',
    verificationState: 'none',
    createdAt: new Date().toISOString(),
  };
  tasks.set(task.taskId, task);
  persistTasks();
  return task;
}

export function getTask(taskId: string): GovernedTask | undefined {
  return tasks.get(taskId);
}

export function listTasks(limit = MAX_TASKS): GovernedTask[] {
  return [...tasks.values()]
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .slice(0, limit);
}

export function updateTask(taskId: string, patch: Partial<GovernedTask>): GovernedTask | undefined {
  const current = tasks.get(taskId);
  if (!current) return undefined;
  const next: GovernedTask = {
    ...current,
    ...patch,
    status: patch.status ? normalizeTaskStatus(patch.status) : current.status,
    verificationState: patch.verificationState
      ? normalizeVerificationState(patch.verificationState)
      : current.verificationState,
  };
  tasks.set(taskId, next);
  persistTasks();
  return next;
}

export function clearAllTasks(): void {
  tasks.clear();
  persistTasks();
}
