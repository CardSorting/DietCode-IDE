import { spawn, type ChildProcess } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { emitBridgeEvent, normalizeTaskRunnerRecord, broadcastEvent } from './events.js';
import { createTask, getTask, updateTask } from './taskRegistry.js';
import type { GovernedTask } from './taskRegistry.js';
import { finalizeTaskAfterAgentStop } from './verifyGate.js';

const BRIDGE_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(BRIDGE_DIR, '../..');

const runningTasks = new Set<string>();
const taskProcesses = new Map<string, ChildProcess>();

function resolveGovernedTaskScript(): string {
  const candidates = [
    join(REPO_ROOT, 'scripts', 'cockpit_governed_task.py'),
    join(REPO_ROOT, 'build', 'resources', 'bin', 'cockpit_governed_task.py'),
  ];
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  return candidates[0];
}

function resolveKernelBinary(): string | undefined {
  const candidates = [
    process.env.DIETCODE_KERNEL_PATH,
    join(REPO_ROOT, 'build', 'dietcode-kernel'),
    join(REPO_ROOT, 'build', 'DietCode.app', 'Contents', 'MacOS', 'DietCode'),
  ].filter(Boolean) as string[];
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  return undefined;
}

export function isTaskRunning(taskId: string): boolean {
  return runningTasks.has(taskId);
}

function attachRunner(task: GovernedTask, child: ChildProcess): void {
  let stderr = '';

  child.stdout?.on('data', (chunk: Buffer) => {
    const lines = chunk.toString('utf8').split('\n');
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const record = JSON.parse(line) as Record<string, unknown>;
        const event = normalizeTaskRunnerRecord(record);
        broadcastEvent(event);

        if (record.type === 'approval.required' && record.taskId) {
          setTaskAwaitingApproval(
            String(record.taskId),
            typeof record.approvalId === 'string' ? record.approvalId : undefined,
          );
        }
        if (record.type === 'approval.resolved' && record.taskId) {
          clearTaskAwaitingApproval(String(record.taskId));
        }

        if (record.type === 'task.completed') {
          runningTasks.delete(task.taskId);
          taskProcesses.delete(task.taskId);
          finalizeTaskAfterAgentStop(task.taskId, Number(record.exitCode ?? 0));
        }
        if (record.type === 'task.failed') {
          runningTasks.delete(task.taskId);
          taskProcesses.delete(task.taskId);
          updateTask(task.taskId, {
            status: 'failed',
            finishedAt: new Date().toISOString(),
            exitCode: Number(record.exitCode ?? 1),
            error: String(record.error ?? 'Agent process failed'),
          });
        }
      } catch {
        emitBridgeEvent('agent.message', line.slice(0, 240), {
          taskId: task.taskId,
          text: line,
          role: 'system',
        });
      }
    }
  });

  child.stderr?.on('data', (chunk: Buffer) => {
    stderr += chunk.toString('utf8');
  });

  child.on('close', (code, signal) => {
    runningTasks.delete(task.taskId);
    taskProcesses.delete(task.taskId);
    const current = getTask(task.taskId);
    if (!current) return;

    if (current.status === 'cancelled') {
      emitBridgeEvent('task.cancelled', 'Task cancelled by user', { taskId: task.taskId });
      return;
    }

    if (current.status === 'running' || current.status === 'awaiting_approval') {
      if (signal === 'SIGTERM' || signal === 'SIGKILL') {
        updateTask(task.taskId, {
          status: 'cancelled',
          finishedAt: new Date().toISOString(),
          error: 'Agent process terminated',
        });
        emitBridgeEvent('task.cancelled', 'Agent process terminated', { taskId: task.taskId });
        return;
      }

      if ((code ?? 1) === 0) {
        const finalized = finalizeTaskAfterAgentStop(task.taskId, 0);
        if (finalized?.status === 'completed') {
          emitBridgeEvent('task.completed', 'Task completed', { taskId: task.taskId });
        }
      } else {
        const message =
          stderr.trim() ||
          (code === null ? 'Agent process died unexpectedly' : `Agent exited with code ${code}`);
        updateTask(task.taskId, {
          status: 'failed',
          finishedAt: new Date().toISOString(),
          exitCode: code ?? 1,
          error: message,
        });
        emitBridgeEvent('task.failed', message, { taskId: task.taskId, error: message });
      }
    }
  });
}

export function startGovernedTask(task: GovernedTask): void {
  if (runningTasks.has(task.taskId)) return;
  runningTasks.add(task.taskId);

  updateTask(task.taskId, {
    status: 'running',
    startedAt: new Date().toISOString(),
    error: undefined,
    finishedAt: undefined,
  });

  const script = resolveGovernedTaskScript();
  const kernel = resolveKernelBinary();
  const env = {
    ...process.env,
    DIETCODE_IDE_ROOT: REPO_ROOT,
    ...(kernel ? { DIETCODE_APP_PATH: kernel } : {}),
  };

  const child = spawn(
    'python3',
    [
      script,
      '--task-id',
      task.taskId,
      '--message',
      task.message,
      '--workspace',
      task.workspace,
      '--mode',
      task.mode,
    ],
    { cwd: REPO_ROOT, env, stdio: ['ignore', 'pipe', 'pipe'] },
  );

  taskProcesses.set(task.taskId, child);
  attachRunner(task, child);
}

export function setTaskAwaitingApproval(taskId: string, approvalId?: string): void {
  const task = getTask(taskId);
  if (!task || (task.status !== 'running' && task.status !== 'awaiting_approval')) return;
  updateTask(taskId, {
    status: 'awaiting_approval',
    error: approvalId ? `Awaiting approval ${approvalId}` : 'Awaiting cockpit approval',
  });
}

export function clearTaskAwaitingApproval(taskId: string): void {
  const task = getTask(taskId);
  if (!task || task.status !== 'awaiting_approval') return;
  if (runningTasks.has(taskId)) {
    updateTask(taskId, { status: 'running', error: undefined });
  }
}

export function cancelTask(taskId: string): GovernedTask | undefined {
  const task = getTask(taskId);
  if (!task) return undefined;
  if (
    task.status !== 'running' &&
    task.status !== 'queued' &&
    task.status !== 'awaiting_approval' &&
    task.status !== 'verification_required' &&
    task.status !== 'verification_failed'
  ) {
    return undefined;
  }

  const child = taskProcesses.get(taskId);
  if (child && !child.killed) {
    child.kill('SIGTERM');
  }
  runningTasks.delete(taskId);
  taskProcesses.delete(taskId);

  return updateTask(taskId, {
    status: 'cancelled',
    finishedAt: new Date().toISOString(),
    error: 'Cancelled from cockpit',
  });
}

export function retryTask(taskId: string): GovernedTask | undefined {
  const source = getTask(taskId);
  if (!source) return undefined;
  if (
    ![
      'disconnected',
      'failed',
      'cancelled',
      'completed',
      'verification_required',
      'verification_failed',
    ].includes(source.status)
  ) {
    return undefined;
  }

  const task = createTask({
    message: source.message,
    workspace: source.workspace,
    mode: source.mode,
  });
  startGovernedTask(task);
  return task;
}
