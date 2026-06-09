import { bridgeError } from '../contracts/errors.js';
const DEFAULT_POLL_MS = 2000;
const DEFAULT_TIMEOUT_MS = 30 * 60 * 1000;
function isSupervisedMode() {
    return (process.env.DIETCODE_SUPERVISED === '1' ||
        process.env.DIETCODE_TASK_MODE === 'supervised');
}
function isHeadlessAutoApprove() {
    return process.env.DIETCODE_HEADLESS_AUTO_APPROVE === '1';
}
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
export async function waitForApprovalResolution(transport, approvalId, options = {}) {
    const pollMs = options.pollMs ?? DEFAULT_POLL_MS;
    const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    const started = Date.now();
    while (Date.now() - started < timeoutMs) {
        const envelope = await transport.call('approval.get', { approvalId });
        if (!envelope.ok || !envelope.result) {
            throw bridgeError('approval_invalid', `approval.get failed for ${approvalId}`);
        }
        const approval = (envelope.result.approval ?? {});
        const status = String(approval.status ?? 'pending');
        if (status === 'rejected' || status === 'expired') {
            throw bridgeError('approval_rejected', `Approval ${approvalId} ${status}`, undefined, { recoveryHint: 'retry_mutation_after_review' });
        }
        if (status === 'failed') {
            throw bridgeError('patch_failed', String(approval.executionError ?? 'Approved mutation failed during execution'));
        }
        if (status === 'approved' || status === 'executed') {
            if (approval.executionResult && typeof approval.executionResult === 'object') {
                return approval.executionResult;
            }
            return approval;
        }
        await sleep(pollMs);
    }
    throw bridgeError('approval_timeout', `Timed out waiting for approval ${approvalId}`);
}
async function resolveApprovalHeadless(transport, approvalId) {
    const envelope = await transport.call('approval.resolve', {
        approvalId,
        decision: 'approved',
        reason: 'headless auto-approve',
        resolvedBy: 'dietcode_bridge',
    });
    if (!envelope.ok || !envelope.result) {
        throw bridgeError('approval_invalid', `approval.resolve failed for ${approvalId}`);
    }
    const resolution = (envelope.result.resolution ?? {});
    if (resolution.executionErrorCode) {
        throw bridgeError('patch_failed', String(resolution.executionError ?? 'Approved mutation failed during execution'));
    }
    const execResult = resolution.executionResult;
    if (execResult && typeof execResult === 'object') {
        return execResult;
    }
    return envelope.result;
}
export async function completeApprovedMutation(transport, pendingResult, method, params, options = {}) {
    const approval = (pendingResult.approval ?? {});
    const approvalId = String(approval.approvalId ?? '');
    if (!approvalId) {
        throw bridgeError('approval_invalid', 'approvalRequired response missing approvalId');
    }
    if (!isSupervisedMode()) {
        if (!isHeadlessAutoApprove()) {
            throw bridgeError('approval_required', 'Destructive mutation requires cockpit approval', undefined, { recoveryHint: 'approval.resolve via cockpit' });
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
//# sourceMappingURL=awaitApproval.js.map