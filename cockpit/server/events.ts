import type { ServerResponse } from 'node:http';

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
let bridgeEventSequence = 1_000_000;
let lastKernelEventSequence = 0;

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
  }
}

export function broadcastEvent(event: StreamEvent): void {
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
  broadcastEvent(event);
  return event;
}

export function normalizeKernelEvent(raw: Record<string, unknown>): StreamEvent {
  const payload =
    raw.payload && typeof raw.payload === 'object'
      ? (raw.payload as Record<string, unknown>)
      : undefined;
  const taskId =
    (typeof payload?.taskId === 'string' && payload.taskId) ||
    (typeof payload?.approval?.taskId === 'string' && (payload.approval as Record<string, unknown>).taskId) ||
    (typeof payload?.resolution?.taskId === 'string' &&
      (payload.resolution as Record<string, unknown>).taskId) ||
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
    sequence: bridgeEventSequence++,
    timestamp: String(record.timestamp ?? new Date().toISOString()),
    type,
    source: String(record.source ?? 'governed-task'),
    detail,
    payload: record,
    taskId: taskId || undefined,
  };
}
