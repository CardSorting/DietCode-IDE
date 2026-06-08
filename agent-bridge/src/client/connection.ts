import { DietCodeBridgeError } from '../contracts/BridgeError.js';
import type { RpcCaller } from './RpcTransport.js';
import { resolveAppPath } from './config.js';
import type { TransportOptions } from '../contracts/types.js';

export interface ReadyState {
  ok: boolean;
  socketPath: string;
  tokenPath: string;
  rpcReady: boolean;
  latencyMs: number;
}

export async function waitForReady(
  transport: RpcCaller,
  options: { timeoutMs?: number; intervalMs?: number } = {},
): Promise<ReadyState> {
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
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
    }
    await sleep(intervalMs);
  }

  throw new DietCodeBridgeError('runtime_unavailable', `runtime not ready: ${lastError}`);
}

export function resolveConnectOptions(options: TransportOptions = {}): TransportOptions {
  return {
    ...options,
    appPath: options.appPath ?? resolveAppPath(),
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
