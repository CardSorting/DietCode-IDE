import type { ServerResponse } from 'node:http';

import {
  getSessionMeta,
  recordSessionEvent,
  setSessionBridgeSequence,
  setSessionKernelSequence,
} from './sessionStore.js';

export interface StreamEvent {
  id: string;
  sequence: number;
  timestamp: string;
  type: string;
  source: string;
  detail: string;
  payload?: Record<string, unknown>;
  taskId?: string;
}

const sseClients = new Set<ServerResponse>();
let bridgeEventSequence = getSessionMeta().bridgeEventSequence;
let lastKernelEventSequence = getSessionMeta().lastKernelEventSequence;

export function hydrateEventSequences(meta: {
  bridgeEventSequence: number;
  lastKernelEventSequence: number;
}): void {
  bridgeEventSequence = Math.max(bridgeEventSequence, meta.bridgeEventSequence);
  lastKernelEventSequence = Math.max(lastKernelEventSequence, meta.lastKernelEventSequence);
}

export function registerSseClient(res: ServerResponse): void {
  sseClients.add(res);
}

export function unregisterSseClient(res: ServerResponse): void {
  sseClients.delete(res);
}

export function getLastKernelEventSequence(): number {
  return lastKernelEventSequence;
}

export function setLastKernelEventSequence(sequence: number): void {
  if (sequence > lastKernelEventSequence) {
    lastKernelEventSequence = sequence;
    setSessionKernelSequence(sequence);
  }
}

export function broadcastEvent(event: StreamEvent): void {
  recordSessionEvent(event);
  const frame = `data: ${JSON.stringify(event)}\n\n`;
  for (const client of sseClients) {
    client.write(frame);
  }
}

export function emitBridgeEvent(
  type: string,
  detail: string,
  payload: Record<string, unknown> = {},
): StreamEvent {
  const taskId = typeof payload.taskId === 'string' ? payload.taskId : undefined;
  const event: StreamEvent = {
    id: `bridge-${taskId ?? 'system'}-${bridgeEventSequence}`,
    sequence: bridgeEventSequence,
    timestamp: new Date().toISOString(),
    type,
    source: 'bridge',
    detail,
    payload,
    taskId,
  };
  bridgeEventSequence += 1;
  setSessionBridgeSequence(bridgeEventSequence);
  broadcastEvent(event);
  return event;
}

export function normalizeKernelEvent(raw: Record<string, unknown>): StreamEvent {
  const payload =
    raw.payload && typeof raw.payload === 'object'
      ? (raw.payload as Record<string, unknown>)
      : undefined;
  const approval =
    payload?.approval && typeof payload.approval === 'object'
      ? (payload.approval as Record<string, unknown>)
      : undefined;
  const resolution =
    payload?.resolution && typeof payload.resolution === 'object'
      ? (payload.resolution as Record<string, unknown>)
      : undefined;
  const taskId =
    (typeof payload?.taskId === 'string' && payload.taskId) ||
    (typeof approval?.taskId === 'string' && approval.taskId) ||
    (typeof resolution?.taskId === 'string' && resolution.taskId) ||
    undefined;

  return {
    id: String(raw.id ?? `kernel-${String(raw.sequence ?? 0)}`),
    sequence: Number(raw.sequence ?? 0),
    timestamp: String(raw.timestamp ?? new Date().toISOString()),
    type: String(raw.type ?? 'kernel.event'),
    source: String(raw.source ?? 'kernel'),
    detail: String(raw.detail ?? ''),
    payload,
    taskId: typeof taskId === 'string' ? taskId : undefined,
  };
}

export function normalizeTaskRunnerRecord(record: Record<string, unknown>): StreamEvent {
  const type = String(record.type ?? 'task.activity');
  const taskId = String(record.taskId ?? '');
  const detail =
    type === 'agent.message'
      ? String(record.text ?? '').slice(0, 240)
      : type === 'task.failed'
        ? String(record.error ?? 'task failed')
        : type === 'task.completed'
          ? 'Task completed'
          : type === 'tool.call.started'
            ? `Tool: ${String(record.action ?? '')}`
            : type === 'tool.call.completed'
              ? `Tool done: ${String(record.action ?? '')}`
              : type;

  return {
    id: `task-${taskId}-${bridgeEventSequence}`,
    sequence: (() => {
      const seq = bridgeEventSequence++;
      setSessionBridgeSequence(bridgeEventSequence);
      return seq;
    })(),
    timestamp: String(record.timestamp ?? new Date().toISOString()),
    type,
    source: String(record.source ?? 'governed-task'),
    detail,
    payload: record,
    taskId: taskId || undefined,
  };
}
