import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { safePatchFile } from '../workflows/safePatchFile.js';
import { applyJournalAuthorityLabels } from '../adapters/runtimeAdapter.js';
import { MockRpcTransport } from '../testing/MockRpcTransport.js';
const PATH = 'authority_probe.py';
const DIFF = `--- authority_probe.py\n+++ authority_probe.py\n@@ -1 +1 @@\n-old\n+new\n`;
const LIVE_HASH = 'livehash00000001';
const JOURNAL_HASH = 'journalhash000001';
function ok(method, result) {
    return { id: `mock:${method}`, ok: true, result };
}
describe('bridge.authority.safePatch', () => {
    it('always captures beforeContentHash from patch.validate, never journal', async () => {
        const transport = new MockRpcTransport({
            'patch.validate': () => ok('patch.validate', {
                validation: {
                    ok: true,
                    beforeContentHash: LIVE_HASH,
                    patchFingerprint: 'fp1',
                    requiresConfirmation: false,
                },
            }),
            'workspace.revision': () => ok('workspace.revision', { revisionId: 2 }),
            'patch.apply': (_params) => {
                const expectHash = String(_params?.expectBeforeHash ?? '');
                assert.equal(expectHash, LIVE_HASH);
                assert.notEqual(expectHash, JOURNAL_HASH);
                return ok('patch.apply', {
                    applied: true,
                    mutationReceipt: {
                        path: PATH,
                        beforeContentHash: LIVE_HASH,
                        postContentHash: 'posthash00000001',
                        patchFingerprint: 'fp1',
                        readSourceBefore: 'disk',
                        applyChannel: 'disk',
                        atomic: true,
                    },
                });
            },
            'runtime.timeline': () => ok('runtime.timeline', {
                events: [{ receiptHash: JOURNAL_HASH }],
                mode: 'runtime_timeline',
                recordAuthority: 'runtime_journal',
                mutationAuthority: 'cpp_kernel',
                currentStateAuthority: 'workspace_live_read',
                notCurrentFileTruth: true,
            }),
            'memory.operation.findByIdempotencyKey': () => ok('memory.operation.findByIdempotencyKey', {
                receipt: { beforeContentHash: JOURNAL_HASH },
                recordAuthority: 'runtime_journal',
                mutationAuthority: 'cpp_kernel',
                currentStateAuthority: 'workspace_live_read',
                notCurrentFileTruth: true,
            }),
        });
        const result = await safePatchFile(transport, PATH, DIFF, { idempotencyKey: 'auth-key' });
        assert.equal(result.applied, true);
        if (result.applied) {
            assert.equal(result.beforeHashSource, 'live_validate');
            assert.equal(result.beforeContentHash, LIVE_HASH);
        }
        const methods = transport.calls.map((c) => c.method);
        assert.ok(methods.includes('patch.validate'));
        assert.ok(methods.includes('patch.apply'));
        assert.equal(methods.filter((m) => m === 'patch.validate').length, 1);
        assert.equal(methods.filter((m) => m === 'memory.operation.findByIdempotencyKey').length, 0);
        assert.equal(methods.filter((m) => m === 'runtime.timeline').length, 0);
    });
    it('does not auto-retry patch.apply after stale_content', async () => {
        const transport = new MockRpcTransport({
            'patch.validate': () => ok('patch.validate', {
                validation: {
                    ok: true,
                    beforeContentHash: LIVE_HASH,
                    patchFingerprint: 'fp1',
                    requiresConfirmation: false,
                },
            }),
            'workspace.revision': () => ok('workspace.revision', { revisionId: 1 }),
            'patch.apply': () => ({
                id: 'mock:patch.apply',
                ok: false,
                error: {
                    code: 4004,
                    string_code: 'stale_content',
                    message: 'stale',
                    recovery_hint: 'revalidate_patch_with_patch.validate',
                    nextRecommendedCommand: 'patch.validate',
                },
            }),
            'file.stat': () => ok('file.stat', {
                path: PATH,
                contentHash: 'driftedhash00001',
                sizeBytes: 4,
                lineCount: 1,
                modified: 0,
                open: false,
                dirty: false,
                readSource: 'disk',
                isSymlink: false,
                insideWorkspace: true,
                pathEscapesWorkspace: false,
            }),
        });
        const result = await safePatchFile(transport, PATH, DIFF, { idempotencyKey: 'stale-no-retry' });
        assert.equal(result.applied, false);
        if (!result.applied && 'stale' in result && result.stale) {
            assert.equal(result.recoverySource, 'runtime');
            assert.equal(result.nextRecommendedCommand, 'patch.validate');
        }
        assert.equal(transport.calls.filter((c) => c.method === 'patch.apply').length, 1);
    });
    it('labels journal reads as not current file truth', () => {
        const labeled = applyJournalAuthorityLabels({ events: [] });
        assert.equal(labeled.recordAuthority, 'runtime_journal');
        assert.equal(labeled.mutationAuthority, 'cpp_kernel');
        assert.equal(labeled.currentStateAuthority, 'workspace_live_read');
        assert.equal(labeled.notCurrentFileTruth, true);
    });
});
//# sourceMappingURL=bridge.safePatchAuthority.test.js.map