import { bridgeError } from '../contracts/errors.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import type { RpcEnvelope } from '../contracts/types.js';

const DEFAULT_POLL_MS = 2000;
const DEFAULT_TIMEOUT_MS = 30 * 60 * 1000;

function isSupervisedMode(): boolean {
  return (
    process.env.DIETCODE_SUPERVISED === '1' ||
    process.env.DIETCODE_TASK_MODE === 'supervised'
  );
}

function isHeadlessAutoApprove(): boolean {
  return process.env.DIETCODE_HEADLESS_AUTO_APPROVE === '1';
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function waitForApprovalResolution(
  transport: RpcCaller,
  approvalId: string,
  options: { pollMs?: number; timeoutMs?: number } = {},
): Promise<Record<string, unknown>> {
  const pollMs = options.pollMs ?? DEFAULT_POLL_MS;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const started = Date.now();

  while (Date.now() - started < timeoutMs) {
    const envelope = await transport.call('approval.get', { approvalId });
    if (!envelope.ok || !envelope.result) {
      throw bridgeError('approval_invalid', `approval.get failed for ${approvalId}`);
    }
    const approval = (envelope.result.approval ?? {}) as Record<string, unknown>;
    const status = String(approval.status ?? 'pending');

    if (status === 'rejected' || status === 'expired') {
      throw bridgeError(
        'approval_rejected',
        `Approval ${approvalId} ${status}`,
        undefined,
        { recoveryHint: 'retry_mutation_after_review' },
      );
    }

    if (status === 'failed') {
      throw bridgeError(
        'patch_failed',
        String(approval.executionError ?? 'Approved mutation failed during execution'),
      );
    }

    if (status === 'approved' || status === 'executed') {
      if (approval.executionResult && typeof approval.executionResult === 'object') {
        return approval.executionResult as Record<string, unknown>;
      }
      return approval;
    }

    await sleep(pollMs);
  }

  throw bridgeError('approval_timeout', `Timed out waiting for approval ${approvalId}`);
}

async function resolveApprovalHeadless(
  transport: RpcCaller,
  approvalId: string,
): Promise<Record<string, unknown>> {
  const envelope = await transport.call('approval.resolve', {
    approvalId,
    decision: 'approved',
    reason: 'headless auto-approve',
    resolvedBy: 'dietcode_bridge',
  });
  if (!envelope.ok || !envelope.result) {
    throw bridgeError('approval_invalid', `approval.resolve failed for ${approvalId}`);
  }
  const resolution = (envelope.result.resolution ?? {}) as Record<string, unknown>;
  if (resolution.executionErrorCode) {
    throw bridgeError(
      'patch_failed',
      String(resolution.executionError ?? 'Approved mutation failed during execution'),
    );
  }
  const execResult = resolution.executionResult;
  if (execResult && typeof execResult === 'object') {
    return execResult as Record<string, unknown>;
  }
  return envelope.result as Record<string, unknown>;
}

export async function completeApprovedMutation(
  transport: RpcCaller,
  pendingResult: Record<string, unknown>,
  method: string,
  params: Record<string, unknown>,
  options: { pollMs?: number; timeoutMs?: number } = {},
): Promise<RpcEnvelope> {
  const approval = (pendingResult.approval ?? {}) as Record<string, unknown>;
  const approvalId = String(approval.approvalId ?? '');
  if (!approvalId) {
    throw bridgeError('approval_invalid', 'approvalRequired response missing approvalId');
  }

  if (!isSupervisedMode()) {
    if (!isHeadlessAutoApprove()) {
      throw bridgeError(
        'approval_required',
        'Destructive mutation requires cockpit approval',
        undefined,
        { recoveryHint: 'approval.resolve via cockpit' },
      );
    }
    const resolved = await resolveApprovalHeadless(transport, approvalId);
    if (resolved.mutationReceipt) {
      return {
        id: `approval:${approvalId}`,
        ok: true,
        result: resolved,
      };
    }
    const retry = await transport.call(method, {
      ...params,
      approvalId,
    });
    return retry;
  }

  const resolved = await waitForApprovalResolution(transport, approvalId, options);
  if (resolved.mutationReceipt) {
    return {
      id: `approval:${approvalId}`,
      ok: true,
      result: resolved,
    };
  }

  const retry = await transport.call(method, {
    ...params,
    approvalId,
  });
  return retry;
}
