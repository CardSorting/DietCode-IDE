import { mapRpcError } from '../contracts/errors.js';
import { normalizeRpcSuccess } from '../contracts/schemas.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type {
  ActivityOptions,
  BridgeResult,
  OperationStatusResult,
  TimelineOptions,
  VerifyFastResult,
} from '../contracts/types.js';

export async function fetchTimeline(
  transport: RpcCaller,
  options: TimelineOptions = {},
): Promise<BridgeResult<Record<string, unknown>>> {
  const envelope = await transport.call('runtime.timeline', {
    limit: options.limit ?? 20,
    offset: options.offset ?? 0,
    sinceRevision: options.sinceRevision,
    errorsOnly: options.errorsOnly ?? false,
  });
  if (!envelope.ok || !envelope.result) {
    throw mapRpcError(envelope, 'getTimeline');
  }
  return normalizeRpcSuccess(envelope, options.includeRaw);
}

export async function fetchRecentActivity(
  transport: RpcCaller,
  options: ActivityOptions = {},
): Promise<BridgeResult<Record<string, unknown>>> {
  const envelope = await transport.call('workspace.activity', {
    limit: options.limit ?? 20,
    sinceRevision: options.sinceRevision,
  });
  if (!envelope.ok || !envelope.result) {
    throw mapRpcError(envelope, 'getRecentActivity');
  }
  return normalizeRpcSuccess(envelope, options.includeRaw);
}

export async function fetchOperationStatus(
  transport: RpcCaller,
  idempotencyKey: string,
): Promise<OperationStatusResult> {
  const envelope = await transport.call('operation.status', { idempotencyKey });
  if (!envelope.ok || !envelope.result) {
    throw mapRpcError(envelope, 'getOperationStatus');
  }
  const raw = envelope.result;
  return {
    status: (raw.status as OperationStatusResult['status']) ?? 'unknown',
    idempotencyKey,
    revisionBefore: typeof raw.revisionBefore === 'number' ? raw.revisionBefore : undefined,
    revisionAfter: typeof raw.revisionAfter === 'number' ? raw.revisionAfter : undefined,
    changedFiles: Array.isArray(raw.changedFiles)
      ? raw.changedFiles.filter((p): p is string => typeof p === 'string')
      : undefined,
    mutationReceipt: raw.mutationReceipt as OperationStatusResult['mutationReceipt'],
    batchMutationReceipt: raw.batchMutationReceipt as OperationStatusResult['batchMutationReceipt'],
    completedAt: typeof raw.completedAt === 'string' ? raw.completedAt : undefined,
  };
}

export async function verifyFast(transport: RpcCaller): Promise<VerifyFastResult> {
  const started = performance.now();
  const ping = await transport.call('rpc.ping', {}, { timeoutMs: 5_000 });
  const rpcReady = ping.ok === true;
  let runtimeAvailable = false;
  if (rpcReady) {
    const diagnostics = await transport.call('runtime.diagnostics', {}, { timeoutMs: 5_000 });
    runtimeAvailable = diagnostics.ok === true && diagnostics.result?.available === true;
  }
  return {
    ok: rpcReady && runtimeAvailable,
    rpcReady,
    runtimeAvailable,
    latencyMs: Math.round(performance.now() - started),
  };
}

export async function fetchWorkspaceRevision(transport: RpcCaller): Promise<number> {
  const envelope = await transport.call('workspace.revision', {});
  if (!envelope.ok || !envelope.result) {
    throw mapRpcError(envelope, 'workspace.revision');
  }
  return Number(envelope.result.revisionId ?? 0);
}
