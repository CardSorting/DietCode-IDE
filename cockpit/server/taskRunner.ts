import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { emitBridgeEvent, normalizeTaskRunnerRecord, broadcastEvent } from './events.js';
import { updateTask } from './taskRegistry.js';
import type { GovernedTask } from './taskRegistry.js';

const BRIDGE_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(BRIDGE_DIR, '../..');

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

const runningTasks = new Set<string>();

export function isTaskRunning(taskId: string): boolean {
  return runningTasks.has(taskId);
}

export function startGovernedTask(task: GovernedTask): void {
  if (runningTasks.has(task.taskId)) return;
  runningTasks.add(task.taskId);

  updateTask(task.taskId, {
    status: 'running',
    startedAt: new Date().toISOString(),
  });

  const script = resolveGovernedTaskScript();
  const kernel = resolveKernelBinary();
  const env = {
    ...process.env,
    DIETCODE_IDE_ROOT: REPO_ROOT,
    ...(kernel ? { DIETCODE_APP_PATH: kernel } : {}),
  };

  const args = [
    script,
    '--task-id',
    task.taskId,
    '--message',
    task.message,
    '--workspace',
    task.workspace,
    '--mode',
    task.mode,
  ];

  const child = spawn('python3', args, {
    cwd: REPO_ROOT,
    env,
    stdio: ['ignore', 'pipe', 'pipe'],
  });

  let stderr = '';

  child.stdout.on('data', (chunk: Buffer) => {
    const lines = chunk.toString('utf8').split('\n');
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const record = JSON.parse(line) as Record<string, unknown>;
        const event = normalizeTaskRunnerRecord(record);
        broadcastEvent(event);

        if (record.type === 'task.completed') {
          updateTask(task.taskId, {
            status: 'completed',
            finishedAt: new Date().toISOString(),
            exitCode: Number(record.exitCode ?? 0),
          });
        }
        if (record.type === 'task.failed') {
          updateTask(task.taskId, {
            status: 'failed',
            finishedAt: new Date().toISOString(),
            exitCode: Number(record.exitCode ?? 1),
            error: String(record.error ?? 'task failed'),
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

  child.stderr.on('data', (chunk: Buffer) => {
    stderr += chunk.toString('utf8');
  });

  child.on('close', (code) => {
    runningTasks.delete(task.taskId);
    const current = updateTask(task.taskId, {});
    if (current && current.status === 'running') {
      if ((code ?? 1) === 0) {
        updateTask(task.taskId, {
          status: 'completed',
          finishedAt: new Date().toISOString(),
          exitCode: 0,
        });
        emitBridgeEvent('task.completed', 'Task completed', { taskId: task.taskId });
      } else {
        updateTask(task.taskId, {
          status: 'failed',
          finishedAt: new Date().toISOString(),
          exitCode: code ?? 1,
          error: stderr.trim() || `Runner exited ${code}`,
        });
        emitBridgeEvent('task.failed', stderr.trim() || `Runner exited ${code}`, {
          taskId: task.taskId,
          error: stderr.trim() || `Runner exited ${code}`,
        });
      }
    }
  });
}
