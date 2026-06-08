import { DietCodeBridgeError } from '../contracts/BridgeError.js';
import { resolveAppPath } from './config.js';
export async function waitForReady(transport, options = {}) {
    const timeoutMs = options.timeoutMs ?? 10_000;
    const intervalMs = options.intervalMs ?? 200;
    const started = Date.now();
    const deadline = started + timeoutMs;
    let lastError = 'rpc.ping not ready';
    while (Date.now() <= deadline) {
        try {
            const ping = await transport.call('rpc.ping', {}, { timeoutMs: Math.min(2_000, timeoutMs) });
            if (ping.ok) {
                return {
                    ok: true,
                    socketPath: '',
                    tokenPath: '',
                    rpcReady: true,
                    latencyMs: Date.now() - started,
                };
            }
            lastError = ping.error?.message ?? 'rpc.ping failed';
        }
        catch (error) {
            lastError = error instanceof Error ? error.message : String(error);
        }
        await sleep(intervalMs);
    }
    throw new DietCodeBridgeError('runtime_unavailable', `runtime not ready: ${lastError}`);
}
export function resolveConnectOptions(options = {}) {
    return {
        ...options,
        appPath: options.appPath ?? resolveAppPath(),
    };
}
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
//# sourceMappingURL=connection.js.map