import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
export function createTaskCoherenceLogger(source = 'dietcode_bridge') {
    const logPath = process.env.DIETCODE_TASK_EVENT_LOG?.trim();
    if (!logPath) {
        return () => undefined;
    }
    const abs = resolve(logPath);
    return (event) => {
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
        }
        catch {
            // best-effort task telemetry
        }
    };
}
//# sourceMappingURL=coherenceEvents.js.map