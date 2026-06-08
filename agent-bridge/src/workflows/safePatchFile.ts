import { randomUUID } from 'node:crypto';

import { applyPatch, validatePatch } from '../adapters/patchAdapter.js';
import { fetchOperationStatus, fetchWorkspaceRevision } from '../adapters/runtimeAdapter.js';
import { isBridgeError } from '../contracts/BridgeError.js';
import { bridgeError } from '../contracts/errors.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type { MutationReceipt, PatchOptions, SafePatchResult } from '../contracts/types.js';
import { buildStaleRecoveryResponse } from './stalePatchRecovery.js';
import { verifyAfterMutation } from './verifyAfterMutation.js';

export async function safePatchFile(
  transport: RpcCaller,
  path: string,
  unifiedDiff: string,
  options: PatchOptions = {},
): Promise<SafePatchResult> {
  const idempotencyKey = options.idempotencyKey ?? `bridge-patch:${randomUUID()}`;

  const validation = await validatePatch(transport, path, unifiedDiff);
  if (!validation.ok) {
    throw bridgeError('patch_failed', 'patch validation failed before apply');
  }

  const liveBeforeHash = validation.beforeContentHash;
  const revisionBefore = await fetchWorkspaceRevision(transport);

  try {
    const applied = await applyPatch(transport, path, unifiedDiff, liveBeforeHash, {
      ...options,
      idempotencyKey,
    });

    const receipt = applied.result.mutationReceipt as MutationReceipt;
    const verified = await verifyAfterMutation(transport, revisionBefore, receipt);

    return {
      applied: true,
      mutationReceipt: receipt,
      revisionBefore: verified.revisionBefore,
      revisionAfter: verified.revisionAfter,
      idempotencyKey,
      nextRecommendedCommand: applied.nextRecommendedCommand ?? 'workspace.revision',
      beforeHashSource: 'live_validate',
      beforeContentHash: liveBeforeHash,
    };
  } catch (error) {
    if (isBridgeError(error) && error.code === 'stale_content') {
      return buildStaleRecoveryResponse(
        transport,
        path,
        liveBeforeHash,
        idempotencyKey,
        error.rawError,
      );
    }

    if (isBridgeError(error) && error.code === 'nested_call_timeout') {
      const status = await fetchOperationStatus(transport, idempotencyKey);
      if (status.status === 'completed' && status.mutationReceipt) {
        return {
          applied: true,
          mutationReceipt: status.mutationReceipt,
          revisionBefore: status.revisionBefore,
          revisionAfter: status.revisionAfter,
          idempotencyKey,
          nextRecommendedCommand: 'workspace.revision',
          beforeHashSource: 'live_validate',
          beforeContentHash: liveBeforeHash,
        };
      }
      throw error;
    }

    throw error;
  }
}
