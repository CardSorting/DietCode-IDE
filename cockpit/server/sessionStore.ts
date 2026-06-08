import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

import type { StreamEvent } from './events.js';
import type { GovernedTask } from './taskRegistry.js';

const SESSION_DIR =
  process.env.DIETCODE_SESSION_DIR ?? join(homedir(), '.dietcode', 'session');
const MAX_EVENTS = Number(process.env.DIETCODE_SESSION_MAX_EVENTS ?? 300);
const MAX_DIFFS = Number(process.env.DIETCODE_SESSION_MAX_DIFFS ?? 20);
const MAX_TASKS = Number(process.env.DIETCODE_SESSION_MAX_TASKS ?? 40);

const ACTIVE_TASKS_PATH = join(SESSION_DIR, 'active_tasks.json');
const PENDING_APPROVALS_PATH = join(SESSION_DIR, 'pending_approvals.json');
const RECENT_EVENTS_PATH = join(SESSION_DIR, 'recent_events.ndjson');
const RECENT_DIFFS_PATH = join(SESSION_DIR, 'recent_diffs.json');

export interface RecentDiff {
  path: string;
  preview?: string;
  taskId?: string;
  timestamp: string;
}

export interface SessionSnapshot {
  restoredAt: string;
  events: StreamEvent[];
  tasks: GovernedTask[];
  pendingApprovals: Record<string, unknown>[];
  recentDiffs: RecentDiff[];
  activeTaskId?: string;
  meta: {
    lastKernelEventSequence: number;
    bridgeEventSequence: number;
    eventCount: number;
  };
}

let eventRing: StreamEvent[] = [];
let recentDiffs: RecentDiff[] = [];
let pendingApprovals: Record<string, unknown>[] = [];
let lastKernelEventSequence = 0;
let bridgeEventSequence = 1_000_000;
let taskCounter = 0;
let persistTimer: NodeJS.Timeout | null = null;
let initialized = false;

async function ensureSessionDir(): Promise<void> {
  await mkdir(SESSION_DIR, { recursive: true });
}

function schedulePersist(): void {
  if (persistTimer) return;
  persistTimer = setTimeout(() => {
    persistTimer = null;
    void flushToDisk();
  }, 400);
}

async function readJsonFile<T>(path: string, fallback: T): Promise<T> {
  if (!existsSync(path)) return fallback;
  try {
    const raw = await readFile(path, 'utf8');
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

async function loadRecentEvents(): Promise<StreamEvent[]> {
  if (!existsSync(RECENT_EVENTS_PATH)) return [];
  try {
    const raw = await readFile(RECENT_EVENTS_PATH, 'utf8');
    const events: StreamEvent[] = [];
    for (const line of raw.split('\n')) {
      if (!line.trim()) continue;
      try {
        events.push(JSON.parse(line) as StreamEvent);
      } catch {
        // skip corrupt line
      }
    }
    return events.slice(-MAX_EVENTS);
  } catch {
    return [];
  }
}

async function rewriteRecentEvents(): Promise<void> {
  await ensureSessionDir();
  const body = eventRing.map((event) => JSON.stringify(event)).join('\n');
  const suffix = body.length > 0 ? '\n' : '';
  await writeFile(RECENT_EVENTS_PATH, body + suffix, 'utf8');
}

export function getSessionEventRing(): StreamEvent[] {
  return [...eventRing];
}

export function getSessionRecentDiffs(): RecentDiff[] {
  return [...recentDiffs];
}

export function getSessionPendingApprovals(): Record<string, unknown>[] {
  return [...pendingApprovals];
}

export function getSessionMeta(): {
  lastKernelEventSequence: number;
  bridgeEventSequence: number;
  taskCounter: number;
} {
  return { lastKernelEventSequence, bridgeEventSequence, taskCounter };
}

export function setSessionKernelSequence(sequence: number): void {
  if (sequence > lastKernelEventSequence) {
    lastKernelEventSequence = sequence;
    schedulePersist();
  }
}

export function setSessionBridgeSequence(sequence: number): void {
  if (sequence >= bridgeEventSequence) {
    bridgeEventSequence = sequence + 1;
  }
}

export function setSessionTaskCounter(counter: number): void {
  if (counter > taskCounter) {
    taskCounter = counter;
  }
}

export function nextSessionTaskId(): string {
  taskCounter += 1;
  return `task_${taskCounter}`;
}

export function recordSessionEvent(event: StreamEvent): void {
  eventRing.push(event);
  if (eventRing.length > MAX_EVENTS) {
    eventRing = eventRing.slice(-MAX_EVENTS);
  }
  if (event.sequence >= 1_000_000) {
    setSessionBridgeSequence(event.sequence);
  } else if (event.source === 'kernel') {
    setSessionKernelSequence(event.sequence);
  }

  if (event.type === 'file.diff') {
    const path = String(event.payload?.path ?? event.detail ?? 'unknown');
    const preview =
      typeof event.payload?.preview === 'string'
        ? event.payload.preview
        : typeof event.payload?.patch === 'string'
          ? event.payload.patch
          : undefined;
    recentDiffs.unshift({
      path,
      preview: preview?.slice(0, 4000),
      taskId: event.taskId,
      timestamp: event.timestamp,
    });
    if (recentDiffs.length > MAX_DIFFS) {
      recentDiffs = recentDiffs.slice(0, MAX_DIFFS);
    }
  }

  schedulePersist();
}

export function setSessionPendingApprovals(approvals: Record<string, unknown>[]): void {
  pendingApprovals = approvals.slice(0, 50);
  schedulePersist();
}

export async function persistActiveTasks(tasks: GovernedTask[]): Promise<void> {
  await ensureSessionDir();
  const trimmed = tasks
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .slice(0, MAX_TASKS);
  await writeFile(
    ACTIVE_TASKS_PATH,
    JSON.stringify(
      {
        version: 1,
        updatedAt: new Date().toISOString(),
        taskCounter,
        tasks: trimmed,
      },
      null,
      2,
    ),
    'utf8',
  );
}

async function flushToDisk(): Promise<void> {
  try {
    await ensureSessionDir();
    await rewriteRecentEvents();
    await writeFile(
      PENDING_APPROVALS_PATH,
      JSON.stringify(
        {
          version: 1,
          updatedAt: new Date().toISOString(),
          approvals: pendingApprovals,
        },
        null,
        2,
      ),
      'utf8',
    );
    await writeFile(
      RECENT_DIFFS_PATH,
      JSON.stringify(
        {
          version: 1,
          updatedAt: new Date().toISOString(),
          diffs: recentDiffs,
        },
        null,
        2,
      ),
      'utf8',
    );
  } catch {
    // session recovery is best-effort
  }
}

export async function initSessionStore(): Promise<{
  tasks: GovernedTask[];
  events: StreamEvent[];
}> {
  if (initialized) {
    return { tasks: [], events: getSessionEventRing() };
  }
  initialized = true;

  await ensureSessionDir();

  const tasksFile = await readJsonFile<{
    taskCounter?: number;
    tasks?: GovernedTask[];
  }>(ACTIVE_TASKS_PATH, {});

  if (tasksFile.taskCounter && tasksFile.taskCounter > 0) {
    taskCounter = tasksFile.taskCounter;
  } else if (tasksFile.tasks?.length) {
    const maxId = tasksFile.tasks.reduce((max, task) => {
      const match = /^task_(\d+)$/.exec(task.taskId);
      return match ? Math.max(max, Number(match[1])) : max;
    }, 0);
    taskCounter = Math.max(taskCounter, maxId);
  }

  const approvalsFile = await readJsonFile<{ approvals?: Record<string, unknown>[] }>(
    PENDING_APPROVALS_PATH,
    {},
  );
  pendingApprovals = approvalsFile.approvals ?? [];

  const diffsFile = await readJsonFile<{ diffs?: RecentDiff[] }>(RECENT_DIFFS_PATH, {});
  recentDiffs = (diffsFile.diffs ?? []).slice(0, MAX_DIFFS);

  eventRing = await loadRecentEvents();
  for (const event of eventRing) {
    if (event.sequence >= 1_000_000) {
      bridgeEventSequence = Math.max(bridgeEventSequence, event.sequence + 1);
    } else if (event.source === 'kernel') {
      lastKernelEventSequence = Math.max(lastKernelEventSequence, event.sequence);
    }
  }

  const restoredTasks = (tasksFile.tasks ?? []).map((task) => {
    if (task.status === 'running') {
      return {
        ...task,
        status: 'disconnected' as const,
        error: task.error ?? 'Bridge restarted while task was running',
        finishedAt: task.finishedAt ?? new Date().toISOString(),
      };
    }
    return task;
  });

  return { tasks: restoredTasks, events: eventRing };
}

export function buildSessionSnapshot(tasks: GovernedTask[]): SessionSnapshot {
  const running = tasks.find((t) => t.status === 'running');
  const disconnected = tasks.find((t) => t.status === 'disconnected');
  return {
    restoredAt: new Date().toISOString(),
    events: getSessionEventRing(),
    tasks,
    pendingApprovals: getSessionPendingApprovals(),
    recentDiffs: getSessionRecentDiffs(),
    activeTaskId: running?.taskId ?? disconnected?.taskId,
    meta: {
      lastKernelEventSequence,
      bridgeEventSequence,
      eventCount: eventRing.length,
    },
  };
}

export async function exportSessionBundle(tasks: GovernedTask[]): Promise<string> {
  await ensureSessionDir();
  const exportsDir = join(homedir(), '.dietcode', 'exports');
  await mkdir(exportsDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const path = join(exportsDir, `session_export_${stamp}.json`);
  const bundle = {
    exportedAt: new Date().toISOString(),
    kind: 'dietcode_session_export',
    ...buildSessionSnapshot(tasks),
  };
  await writeFile(path, JSON.stringify(bundle, null, 2), 'utf8');
  return path;
}
