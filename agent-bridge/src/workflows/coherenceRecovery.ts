import { resolveBridgeRecovery } from '../contracts/BridgeError.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import { readFileWithCoherence } from '../adapters/fileAdapter.js';
import type {
  CoherenceOperatorRequired,
  CoherenceRecoveryEvent,
  CoherenceStaleRecovery,
  CoherenceToken,
} from '../contracts/types.js';

export interface CoherenceMismatchDetail {
  reason: string;
  changedPaths: string[];
  requiredAction?: string;
  currentWorkspaceRevision?: number;
}

export function parseCoherenceMismatch(
  rawError?: Record<string, unknown>,
): CoherenceMismatchDetail {
  const coherence =
    rawError?.coherence && typeof rawError.coherence === 'object'
      ? (rawError.coherence as Record<string, unknown>)
      : undefined;
  const changedPathsRaw = rawError?.changedPaths ?? coherence?.changedPaths;
  const changedPaths = Array.isArray(changedPathsRaw)
    ? changedPathsRaw.filter((p): p is string => typeof p === 'string' && p.length > 0)
    : [];
  const reason =
    (typeof rawError?.reason === 'string' && rawError.reason) ||
    (typeof coherence?.reason === 'string' && coherence.reason) ||
    'unknown';
  return {
    reason,
    changedPaths,
    requiredAction:
      typeof rawError?.requiredAction === 'string'
        ? rawError.requiredAction
        : typeof coherence?.requiredAction === 'string'
          ? coherence.requiredAction
          : undefined,
    currentWorkspaceRevision:
      typeof rawError?.currentWorkspaceRevision === 'number'
        ? rawError.currentWorkspaceRevision
        : typeof coherence?.currentWorkspaceRevision === 'number'
          ? coherence.currentWorkspaceRevision
          : undefined,
  };
}

export function buildCoherenceStaleRecovery(
  path: string,
  idempotencyKey: string,
  detail: CoherenceMismatchDetail,
  rawError?: Record<string, unknown>,
): CoherenceStaleRecovery {
  const resolved = resolveBridgeRecovery('coherence_mismatch', rawError, { retrySafe: true });
  return {
    applied: false,
    coherenceStale: true,
    operatorInterventionRequired: false,
    path,
    reason: detail.reason,
    changedPaths: detail.changedPaths,
    recoveryHint: resolved.recoveryHint,
    nextRecommendedCommand: resolved.nextRecommendedCommand,
    recoverySource: resolved.recoverySource,
    nextCommandSource: resolved.nextCommandSource,
    idempotencyKey,
  };
}

export function buildCoherenceOperatorRequired(
  path: string,
  idempotencyKey: string,
  detail: CoherenceMismatchDetail,
  rawError?: Record<string, unknown>,
): CoherenceOperatorRequired {
  const resolved = resolveBridgeRecovery('coherence_mismatch', rawError, { retrySafe: false });
  return {
    applied: false,
    coherenceStale: true,
    operatorInterventionRequired: true,
    path,
    reason: detail.reason,
    changedPaths: detail.changedPaths,
    recoveryHint: resolved.recoveryHint,
    nextRecommendedCommand: resolved.nextRecommendedCommand,
    recoverySource: resolved.recoverySource,
    nextCommandSource: resolved.nextCommandSource,
    idempotencyKey,
  };
}

export async function refreshCoherenceContext(
  transport: RpcCaller,
  taskId: string,
  paths: string[],
  emit?: (event: CoherenceRecoveryEvent) => void,
): Promise<{ path: string; text: string; coherence: CoherenceToken }> {
  const primary = paths[0];
  if (!primary) {
    throw new Error('refreshCoherenceContext requires at least one path');
  }

  let latest: { path: string; text: string; coherence: CoherenceToken } | undefined;
  for (const relPath of paths) {
    const read = await readFileWithCoherence(transport, relPath, taskId);
    latest = { path: relPath, text: read.text, coherence: read.coherence };
    emit?.({
      type: 'context.refreshed',
      path: relPath,
      taskId,
      tokenId: read.coherence.tokenId,
    });
  }

  if (!latest) {
    const read = await readFileWithCoherence(transport, primary, taskId);
    latest = { path: primary, text: read.text, coherence: read.coherence };
  }
  return latest;
}
