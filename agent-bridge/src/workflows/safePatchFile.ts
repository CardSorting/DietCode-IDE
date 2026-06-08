import { randomUUID } from 'node:crypto';

import { applyPatch, validatePatch } from '../adapters/patchAdapter.js';
import { fetchOperationStatus, fetchWorkspaceRevision } from '../adapters/runtimeAdapter.js';
import { isBridgeError } from '../client/RpcTransport.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import { mapRpcError } from '../contracts/errors.js';
import type {
  BridgeError,
  RpcEnvelope,
  MutationReceipt,
  PatchOptions,
  SafePatchResult,
} from '../contracts/types.js';
import { buildStaleRecoveryResponse } from './stalePatchRecovery.js';

export async function safePatchFile(
  transport: RpcCaller,
  path: string,
  unifiedDiff: string,
  options: PatchOptions = {},
): Promise<SafePatchResult> {
  const idempotencyKey = options.idempotencyKey ?? `bridge-patch:${randomUUID()}`;

  const validation = await validatePatch(transport, path, unifiedDiff);
  if (!validation.ok) {
    const err: BridgeError = {
      code: 'patch_failed',
      message: 'patch validation failed before apply',
      recoveryHint: 'run_patch_preview_or_patch_validate',
      nextRecommendedCommand: 'patch.validate',
      retrySafe: false,
    };
    throw err;
  }

  const revisionBefore = await fetchWorkspaceRevision(transport);

  try {
    const applied = await applyPatch(transport, path, unifiedDiff, validation.beforeContentHash, {
      ...options,
      idempotencyKey,
    });

    const receipt = applied.result.mutationReceipt as MutationReceipt;
    const revisionAfter = await fetchWorkspaceRevision(transport);

    return {
      applied: true,
      mutationReceipt: receipt,
      revisionBefore,
      revisionAfter,
      idempotencyKey,
      nextRecommendedCommand: applied.nextRecommendedCommand ?? 'workspace.revision',
    };
  } catch (error) {
    if (isBridgeError(error) && error.code === 'stale_content') {
      return buildStaleRecoveryResponse(
        transport,
        path,
        validation.beforeContentHash,
        idempotencyKey,
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
        };
      }
      throw error;
    }

    if (
      typeof error === 'object' &&
      error !== null &&
      'ok' in error &&
      (error as { ok?: boolean }).ok === false
    ) {
      throw mapRpcError(error as RpcEnvelope);
    }

    throw error;
  }
}
