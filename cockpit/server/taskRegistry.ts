import { nextSessionTaskId, persistActiveTasks } from './sessionStore.js';

export type TaskMode = 'supervised' | 'trusted';
export type TaskStatus =
  | 'queued'
  | 'running'
  | 'awaiting_approval'
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
  createdAt: string;
  startedAt?: string;
  finishedAt?: string;
  exitCode?: number;
  error?: string;
}

const tasks = new Map<string, GovernedTask>();
const MAX_TASKS = 40;

function persistTasks(): void {
  void persistActiveTasks(listTasks(MAX_TASKS));
}

export function normalizeTaskStatus(status: string): TaskStatus {
  if (status === 'pending') return 'queued';
  if (
    status === 'queued' ||
    status === 'running' ||
    status === 'awaiting_approval' ||
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
  };
  tasks.set(taskId, next);
  persistTasks();
  return next;
}

export function clearAllTasks(): void {
  tasks.clear();
  persistTasks();
}
