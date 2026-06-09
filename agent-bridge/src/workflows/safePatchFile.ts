import { randomUUID } from 'node:crypto';

import { applyPatch, validatePatch } from '../adapters/patchAdapter.js';
import { readFileWithCoherence } from '../adapters/fileAdapter.js';
import { fetchOperationStatus, fetchWorkspaceRevision } from '../adapters/runtimeAdapter.js';
import { isBridgeError } from '../contracts/BridgeError.js';
import { bridgeError } from '../contracts/errors.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type { MutationReceipt, PatchOptions, SafePatchResult } from '../contracts/types.js';
import { createTaskCoherenceLogger } from '../telemetry/coherenceEvents.js';
import { recordMutationPatchApplied } from '../telemetry/mutationTelemetry.js';
import { buildLineReplacementPatchFromContent } from '../utils/unifiedDiff.js';
import {
  buildCoherenceOperatorRequired,
  buildCoherenceStaleRecovery,
  parseCoherenceMismatch,
  refreshCoherenceContext,
  type CoherenceMismatchDetail,
} from './coherenceRecovery.js';
import { buildStaleRecoveryResponse } from './stalePatchRecovery.js';
import { verifyAfterMutation } from './verifyAfterMutation.js';

function resolvePatchOptions(options: PatchOptions): PatchOptions {
  const taskId = options.taskId ?? (process.env.DIETCODE_TASK_ID?.trim() || undefined);
  const onCoherenceEvent = options.onCoherenceEvent ?? createTaskCoherenceLogger();
  let buildPatchFromContent = options.buildPatchFromContent;
  if (!buildPatchFromContent && options.lineReplacement) {
    const { search, replace } = options.lineReplacement;
    buildPatchFromContent = ({ path, content }) =>
      buildLineReplacementPatchFromContent(path, content, search, replace);
  }
  return { ...options, taskId, onCoherenceEvent, buildPatchFromContent };
}

async function resolveCoherenceForApply(
  transport: RpcCaller,
  path: string,
  options: PatchOptions,
): Promise<Pick<PatchOptions, 'coherenceTokenId' | 'expectedWorkspaceRevision'>> {
  if (!options.taskId) {
    return {};
  }
  if (options.coherenceTokenId && options.expectedWorkspaceRevision != null) {
    return {
      coherenceTokenId: options.coherenceTokenId,
      expectedWorkspaceRevision: options.expectedWorkspaceRevision,
    };
  }
  const read = await readFileWithCoherence(transport, path, options.taskId);
  return {
    coherenceTokenId: read.coherence.tokenId,
    expectedWorkspaceRevision: read.coherence.workspaceRevision,
  };
}

export async function safePatchFile(
  transport: RpcCaller,
  path: string,
  unifiedDiff: string,
  options: PatchOptions = {},
): Promise<SafePatchResult> {
  const resolved = resolvePatchOptions(options);
  const idempotencyKey = resolved.idempotencyKey ?? `bridge-patch:${randomUUID()}`;
  const emit = (event: Parameters<NonNullable<PatchOptions['onCoherenceEvent']>>[0]) =>
    resolved.onCoherenceEvent?.(event);

  const applyOnce = async (diff: string, patchOptions: PatchOptions): Promise<SafePatchResult> => {
    const validation = await validatePatch(transport, path, diff);
    if (!validation.ok) {
      throw bridgeError('patch_failed', 'patch validation failed before apply');
    }

    const liveBeforeHash = validation.beforeContentHash;
    const revisionBefore = await fetchWorkspaceRevision(transport);
    const coherenceFields = await resolveCoherenceForApply(transport, path, patchOptions);

    try {
      const applied = await applyPatch(transport, path, diff, liveBeforeHash, {
        ...patchOptions,
        ...coherenceFields,
        idempotencyKey,
      });

      const receipt = applied.result.mutationReceipt as MutationReceipt;
      const verified = await verifyAfterMutation(transport, revisionBefore, receipt);

      recordMutationPatchApplied({
        workspace: process.env.DIETCODE_WORKSPACE ?? process.env.HERMES_KANBAN_WORKSPACE ?? '',
        path: receipt.path,
        beforeHash: receipt.beforeContentHash,
        afterHash: receipt.postContentHash,
        tool: 'dietcode_ide.patch',
        protocol: 'safePatchFile',
        idempotencyKey,
      });

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
      throw error;
    }
  };

  const recoverAndRetryCoherence = async (
    detail: CoherenceMismatchDetail,
    rawError?: Record<string, unknown>,
  ): Promise<SafePatchResult> => {
    emit({
      type: 'context.stale',
      path,
      taskId: resolved.taskId,
      reason: detail.reason,
      changedPaths: detail.changedPaths,
    });

    if (!resolved.taskId || !resolved.buildPatchFromContent) {
      return buildCoherenceStaleRecovery(path, idempotencyKey, detail, rawError);
    }

    const refreshPaths = detail.changedPaths.length > 0 ? detail.changedPaths : [path];
    const refreshed = await refreshCoherenceContext(
      transport,
      resolved.taskId,
      refreshPaths,
      emit,
    );
    const regenerated = resolved.buildPatchFromContent({
      path,
      content: refreshed.text,
    });

    emit({
      type: 'coherence.retry',
      path,
      taskId: resolved.taskId,
      attempt: 1,
      tokenId: refreshed.coherence.tokenId,
    });

    try {
      return await applyOnce(regenerated, {
        ...resolved,
        coherenceTokenId: refreshed.coherence.tokenId,
        expectedWorkspaceRevision: refreshed.coherence.workspaceRevision,
      });
    } catch (retryError) {
      if (isBridgeError(retryError) && retryError.code === 'coherence_mismatch') {
        const retryDetail = parseCoherenceMismatch(retryError.rawError);
        emit({
          type: 'coherence.operator_required',
          path,
          taskId: resolved.taskId,
          reason: retryDetail.reason,
          changedPaths: retryDetail.changedPaths,
        });
        return buildCoherenceOperatorRequired(
          path,
          idempotencyKey,
          retryDetail,
          retryError.rawError,
        );
      }
      throw retryError;
    }
  };

  const initialValidation = await validatePatch(transport, path, unifiedDiff);
  if (!initialValidation.ok) {
    if (resolved.taskId && resolved.buildPatchFromContent) {
      return recoverAndRetryCoherence({
        reason: 'patch_validate_failed',
        changedPaths: [path],
      });
    }
    throw bridgeError('patch_failed', 'patch validation failed before apply');
  }

  try {
    return await applyOnce(unifiedDiff, resolved);
  } catch (error) {
    if (isBridgeError(error) && error.code === 'coherence_mismatch') {
      return recoverAndRetryCoherence(parseCoherenceMismatch(error.rawError), error.rawError);
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
          beforeContentHash: status.mutationReceipt.beforeContentHash,
        };
      }
      throw error;
    }

    throw error;
  }
}
