import { randomUUID } from 'node:crypto';

import { applyPatchBatch, validatePatch, type BatchPatchRpcEntry } from '../adapters/patchAdapter.js';
import { fetchFileStat } from '../adapters/diagnosticsAdapter.js';
import { fetchOperationStatus, fetchWorkspaceRevision } from '../adapters/runtimeAdapter.js';
import { isBridgeError } from '../client/RpcTransport.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type {
  BatchMutationReceipt,
  BatchPatchOptions,
  PatchBatchEntry,
  SafeBatchPatchResult,
} from '../contracts/types.js';

export async function safePatchBatch(
  transport: RpcCaller,
  patches: PatchBatchEntry[],
  options: BatchPatchOptions = {},
): Promise<SafeBatchPatchResult> {
  const idempotencyKey = options.idempotencyKey ?? `bridge-batch:${randomUUID()}`;
  const rpcPatches: BatchPatchRpcEntry[] = [];
  const hashesBefore = new Map<string, string>();

  for (const entry of patches) {
    const validation = await validatePatch(transport, entry.path, entry.unifiedDiff);
    if (!validation.ok) {
      return {
        applied: false,
        atomic: true,
        rolledBack: true,
        failedPath: entry.path,
        idempotencyKey,
        recoveryHint: 'run_patch_preview_or_patch_validate',
        nextRecommendedCommand: 'patch.validate',
        filesVerifiedUnchanged: true,
      };
    }
    rpcPatches.push({
      path: entry.path,
      patch: entry.unifiedDiff,
      expectBeforeHash: validation.beforeContentHash,
    });
    hashesBefore.set(entry.path, validation.beforeContentHash);
  }

  const revisionBefore = await fetchWorkspaceRevision(transport);

  try {
    const applied = await applyPatchBatch(transport, rpcPatches, {
      ...options,
      idempotencyKey,
    });

    const receipt = applied.result.batchMutationReceipt as BatchMutationReceipt;
    const revisionAfter = await fetchWorkspaceRevision(transport);

    return {
      applied: true,
      atomic: true,
      batchMutationReceipt: receipt,
      idempotencyKey,
      revisionBefore,
      revisionAfter,
      nextRecommendedCommand: applied.nextRecommendedCommand ?? 'workspace.revision',
    };
  } catch (error) {
    if (isBridgeError(error) && error.code === 'nested_call_timeout') {
      const status = await fetchOperationStatus(transport, idempotencyKey);
      if (status.status === 'completed' && status.batchMutationReceipt) {
        return {
          applied: true,
          atomic: true,
          batchMutationReceipt: status.batchMutationReceipt,
          idempotencyKey,
          revisionBefore: status.revisionBefore,
          revisionAfter: status.revisionAfter,
          nextRecommendedCommand: 'workspace.revision',
        };
      }
      throw error;
    }

    const filesVerifiedUnchanged = await verifyFilesUnchanged(transport, hashesBefore);
    const failedPath =
      isBridgeError(error) && error.rawError?.path
        ? String(error.rawError.path)
        : rpcPatches[0]?.path;

    return {
      applied: false,
      atomic: true,
      rolledBack: true,
      failedPath,
      idempotencyKey,
      recoveryHint: isBridgeError(error) ? error.recoveryHint : 'revalidate_batch_with_patch.validate',
      nextRecommendedCommand: isBridgeError(error)
        ? error.nextRecommendedCommand
        : 'patch.validate',
      filesVerifiedUnchanged,
    };
  }
}

async function verifyFilesUnchanged(
  transport: RpcCaller,
  hashesBefore: Map<string, string>,
): Promise<boolean> {
  for (const [path, beforeHash] of hashesBefore) {
    try {
      const stat = await fetchFileStat(transport, path);
      const current = String(stat.result.contentHash ?? '');
      if (current !== beforeHash) {
        return false;
      }
    } catch {
      return false;
    }
  }
  return true;
}
