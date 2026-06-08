import { mapRpcError } from '../contracts/errors.js';
import {
  assertBatchReceipt,
  assertMutationReceipt,
  normalizeRpcSuccess,
} from '../contracts/schemas.js';
import { validateBatchMutationReceipt, validateMutationReceipt } from '../contracts/validators.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type { BatchPatchOptions, BridgeResult, PatchOptions } from '../contracts/types.js';

export interface PatchValidation {
  ok: boolean;
  beforeContentHash: string;
  patchFingerprint: string;
  requiresConfirmation: boolean;
}

export async function validatePatch(
  transport: RpcCaller,
  path: string,
  unifiedDiff: string,
): Promise<PatchValidation> {
  const envelope = await transport.call('patch.validate', { path, patch: unifiedDiff });
  if (!envelope.ok || !envelope.result) {
    throw mapRpcError(envelope, 'validatePatch');
  }
  const validation = envelope.result.validation as Record<string, unknown>;
  return {
    ok: validation.ok === true,
    beforeContentHash: String(validation.beforeContentHash ?? ''),
    patchFingerprint: String(validation.patchFingerprint ?? ''),
    requiresConfirmation: validation.requiresConfirmation === true,
  };
}

export async function applyPatch(
  transport: RpcCaller,
  path: string,
  unifiedDiff: string,
  expectBeforeHash: string,
  options: PatchOptions = {},
): Promise<BridgeResult<Record<string, unknown>>> {
  const envelope = await transport.call(
    'patch.apply',
    {
      path,
      patch: unifiedDiff,
      confirm: true,
      dryRun: options.dryRun ?? false,
      expectBeforeHash,
      idempotencyKey: options.idempotencyKey,
    },
    { timeoutMs: options.requestTimeoutMs },
  );
  if (!envelope.ok || !envelope.result) {
    throw mapRpcError(envelope, 'applyPatch');
  }
  const receipt = envelope.result.mutationReceipt;
  if (receipt && typeof receipt === 'object') {
    assertMutationReceipt(receipt as Record<string, unknown>);
    const errors = validateMutationReceipt(receipt as Record<string, unknown>);
    if (errors.length > 0) {
      throw mapRpcError(
        { id: envelope.id, ok: false, error: { code: -32000, message: errors.join('; ') } },
        'applyPatch',
      );
    }
  }
  return normalizeRpcSuccess(envelope, options.includeRaw);
}

export interface BatchPatchRpcEntry {
  path: string;
  patch: string;
  expectBeforeHash: string;
}

export async function applyPatchBatch(
  transport: RpcCaller,
  patches: BatchPatchRpcEntry[],
  options: BatchPatchOptions = {},
): Promise<BridgeResult<Record<string, unknown>>> {
  const envelope = await transport.call(
    'patch.applyBatch',
    {
      patches,
      dryRun: options.dryRun ?? false,
      confirm: options.confirm ?? true,
      idempotencyKey: options.idempotencyKey,
    },
    { timeoutMs: options.requestTimeoutMs },
  );
  if (!envelope.ok || !envelope.result) {
    throw mapRpcError(envelope, 'applyPatchBatch');
  }
  const receipt = envelope.result.batchMutationReceipt;
  if (receipt && typeof receipt === 'object') {
    assertBatchReceipt(receipt as Record<string, unknown>);
    const errors = validateBatchMutationReceipt(receipt as Record<string, unknown>);
    if (errors.length > 0) {
      throw mapRpcError(
        { id: envelope.id, ok: false, error: { code: -32000, message: errors.join('; ') } },
        'applyPatchBatch',
      );
    }
  }
  return normalizeRpcSuccess(envelope, options.includeRaw);
}
