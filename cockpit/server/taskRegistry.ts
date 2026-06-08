import { nextSessionTaskId, persistActiveTasks } from './sessionStore.js';

export type TaskMode = 'supervised' | 'trusted';
export type TaskStatus = 'pending' | 'running' | 'completed' | 'failed' | 'disconnected';

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

function persistTasks(): void {
  void persistActiveTasks(listTasks(MAX_TASKS));
}

const MAX_TASKS = 40;

export function nextTaskId(): string {
  return nextSessionTaskId();
}

export function restoreTasks(restored: GovernedTask[]): void {
  tasks.clear();
  for (const task of restored) {
    tasks.set(task.taskId, task);
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
    status: 'pending',
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
  const next = { ...current, ...patch };
  tasks.set(taskId, next);
  persistTasks();
  return next;
}
