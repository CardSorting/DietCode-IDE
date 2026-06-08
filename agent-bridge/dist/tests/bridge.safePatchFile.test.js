import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { safePatchFile } from '../workflows/safePatchFile.js';
import { MockRpcTransport } from '../client/RpcTransport.js';
const PATH = 'probe.py';
const DIFF = `--- probe.py\n+++ probe.py\n@@ -1 +1 @@\n-old\n+new\n`;
const BEFORE_HASH = 'abc123hash000001';
function ok(method, result) {
    return { id: `mock:${method}`, ok: true, result };
}
function err(method, stringCode) {
    return {
        id: `mock:${method}`,
        ok: false,
        error: {
            code: 4004,
            string_code: stringCode,
            message: stringCode,
            recovery_hint: 'revalidate_patch_with_patch.validate',
            nextRecommendedCommand: 'patch.validate',
        },
    };
}
describe('bridge.safePatchFile', () => {
    it('returns mutation receipt on successful apply', async () => {
        let revision = 3;
        const transport = new MockRpcTransport({
            'patch.validate': () => ok('patch.validate', {
                validation: {
                    ok: true,
                    beforeContentHash: BEFORE_HASH,
                    patchFingerprint: 'fp1',
                    requiresConfirmation: false,
                },
            }),
            'workspace.revision': () => {
                const current = revision;
                revision += 1;
                return ok('workspace.revision', { revisionId: current });
            },
            'patch.apply': () => ok('patch.apply', {
                applied: true,
                complete: true,
                partial: false,
                warnings: [],
                nextRecommendedCommand: 'workspace.revision',
                mutationReceipt: {
                    path: PATH,
                    beforeContentHash: BEFORE_HASH,
                    postContentHash: 'posthash00000001',
                    patchFingerprint: 'fp1',
                    readSourceBefore: 'disk',
                    applyChannel: 'disk',
                    atomic: true,
                },
            }),
        });
        const result = await safePatchFile(transport, PATH, DIFF, { idempotencyKey: 'key-1' });
        assert.equal(result.applied, true);
        if (result.applied) {
            assert.equal(result.mutationReceipt.path, PATH);
            assert.equal(result.idempotencyKey, 'key-1');
            assert.ok(result.revisionAfter > result.revisionBefore);
        }
    });
    it('recovers via operation.status after timeout', async () => {
        const transport = new MockRpcTransport({
            'patch.validate': () => ok('patch.validate', {
                validation: {
                    ok: true,
                    beforeContentHash: BEFORE_HASH,
                    patchFingerprint: 'fp1',
                    requiresConfirmation: false,
                },
            }),
            'workspace.revision': () => ok('workspace.revision', { revisionId: 5 }),
            'patch.apply': () => {
                throw {
                    code: 'nested_call_timeout',
                    message: 'timed out',
                    recoveryHint: 'reduce_concurrency_or_retry_later',
                    nextRecommendedCommand: 'operation.status',
                    retrySafe: true,
                };
            },
            'operation.status': () => ok('operation.status', {
                status: 'completed',
                idempotencyKey: 'timeout-key',
                revisionBefore: 4,
                revisionAfter: 5,
                mutationReceipt: {
                    path: PATH,
                    beforeContentHash: BEFORE_HASH,
                    postContentHash: 'posthash00000001',
                    patchFingerprint: 'fp1',
                    readSourceBefore: 'disk',
                    applyChannel: 'disk',
                    atomic: true,
                },
            }),
        });
        const result = await safePatchFile(transport, PATH, DIFF, { idempotencyKey: 'timeout-key' });
        assert.equal(result.applied, true);
    });
});
//# sourceMappingURL=bridge.safePatchFile.test.js.map