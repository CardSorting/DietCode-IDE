import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export interface MutationPatchAppliedEvent {
  workspace: string;
  path: string;
  beforeHash: string;
  afterHash: string;
  tool: string;
  protocol: string;
  idempotencyKey?: string;
}

export function recordMutationPatchApplied(event: MutationPatchAppliedEvent): void {
  const payload = {
    eventType: 'mutation.patch.applied',
    ...event,
  };
  const line = `${JSON.stringify(payload)}\n`;
  const logPath = process.env.DIETCODE_MUTATION_EVENT_LOG?.trim();
  if (logPath) {
    try {
      mkdirSync(dirname(logPath), { recursive: true });
      appendFileSync(logPath, line, 'utf8');
    } catch {
      // Best-effort — audit also uses runtime timeline.
    }
  }
  process.stderr.write(`DIETCODE_MUTATION_EVENT:${line}`);
}
