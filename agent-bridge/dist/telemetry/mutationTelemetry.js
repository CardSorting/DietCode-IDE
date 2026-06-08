import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
export function recordMutationPatchApplied(event) {
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
        }
        catch {
            // Best-effort — audit also uses runtime timeline.
        }
    }
    process.stderr.write(`DIETCODE_MUTATION_EVENT:${line}`);
}
//# sourceMappingURL=mutationTelemetry.js.map