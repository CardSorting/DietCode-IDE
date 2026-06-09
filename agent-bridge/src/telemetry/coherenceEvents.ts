import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

import type { CoherenceRecoveryEvent } from '../contracts/types.js';

export function createTaskCoherenceLogger(
  source = 'dietcode_bridge',
): (event: CoherenceRecoveryEvent) => void {
  const logPath = process.env.DIETCODE_TASK_EVENT_LOG?.trim();
  if (!logPath) {
    return () => undefined;
  }
  const abs = resolve(logPath);
  return (event: CoherenceRecoveryEvent) => {
    const taskId = process.env.DIETCODE_TASK_ID?.trim() || event.taskId || '';
    const record = {
      type: event.type,
      taskId,
      timestamp: new Date().toISOString().replace(/\.\d{3}Z$/, 'Z'),
      source,
      path: event.path,
      reason: event.reason,
      changedPaths: event.changedPaths,
      attempt: event.attempt,
      tokenId: event.tokenId,
    };
    try {
      mkdirSync(dirname(abs), { recursive: true });
      appendFileSync(abs, `${JSON.stringify(record)}\n`, 'utf8');
    } catch {
      // best-effort task telemetry
    }
  };
}
