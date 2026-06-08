export type TaskMode = 'supervised' | 'trusted';
export type TaskStatus = 'pending' | 'running' | 'completed' | 'failed';

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
let taskCounter = 0;

export function nextTaskId(): string {
  taskCounter += 1;
  return `task_${taskCounter}`;
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
  return task;
}

export function getTask(taskId: string): GovernedTask | undefined {
  return tasks.get(taskId);
}

export function listTasks(limit = 50): GovernedTask[] {
  return [...tasks.values()]
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .slice(0, limit);
}

export function updateTask(taskId: string, patch: Partial<GovernedTask>): GovernedTask | undefined {
  const current = tasks.get(taskId);
  if (!current) return undefined;
  const next = { ...current, ...patch };
  tasks.set(taskId, next);
  return next;
}
