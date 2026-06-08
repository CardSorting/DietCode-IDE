import { mapRpcError } from '../contracts/errors.js';
import { normalizeRpcSuccess } from '../contracts/schemas.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type { BridgeResult } from '../contracts/types.js';

export async function fetchDiagnostics(
  transport: RpcCaller,
  includeRaw = false,
): Promise<BridgeResult<Record<string, unknown>>> {
  const envelope = await transport.call('runtime.diagnostics', {});
  if (!envelope.ok || !envelope.result) {
    throw mapRpcError(envelope, 'getDiagnostics');
  }
  return normalizeRpcSuccess(envelope, includeRaw);
}

export async function fetchFileStat(
  transport: RpcCaller,
  path: string,
  includeRaw = false,
): Promise<BridgeResult<Record<string, unknown>>> {
  const envelope = await transport.call('file.stat', { path });
  if (!envelope.ok || !envelope.result) {
    throw mapRpcError(envelope, 'getFileStat');
  }
  return normalizeRpcSuccess(envelope, includeRaw);
}
