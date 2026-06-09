import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { parseSingleLineReplacement } from '../utils/unifiedDiff.js';
import { safePatchFile } from '../workflows/safePatchFile.js';
import { MockRpcTransport } from '../testing/MockRpcTransport.js';
const PATH = 'coherence_probe.py';
const TASK_ID = 'task_coherence_recovery';
const LIVE_HASH_V1 = 'hash00000000000001';
const LIVE_HASH_V3 = 'hash00000000000003';
const POST_HASH = 'posthash00000001';
function ok(method, result) {
    return { id: `mock:${method}`, ok: true, result };
}
function patchForValue(from, to) {
    return (`--- ${PATH}\n` +
        `+++ ${PATH}\n` +
        `@@ -1,1 +1,1 @@\n` +
        `-VALUE = ${from}\n` +
        `+VALUE = ${to}\n`);
}
describe('bridge.coherenceRecovery', () => {
    it('retries once after coherence_mismatch when buildPatchFromContent is provided', async () => {
        let fileText = 'VALUE = 1\n';
        let tokenSeq = 0;
        let readCount = 0;
        const events = [];
        let applyAttempts = 0;
        const transport = new MockRpcTransport({
            'file.read': () => {
                readCount += 1;
                if (readCount > 1) {
                    fileText = 'VALUE = 3\n';
                }
                tokenSeq += 1;
                return ok('file.read', {
                    text: fileText,
                    coherence: {
                        tokenId: `coh_${tokenSeq}`,
                        workspaceRevision: tokenSeq,
                        verifyRevision: 0,
                        anchors: { [PATH]: `fnv1a:${fileText.includes('3') ? LIVE_HASH_V3 : LIVE_HASH_V1}` },
                    },
                });
            },
            'patch.validate': (_params) => ok('patch.validate', {
                validation: {
                    ok: true,
                    beforeContentHash: fileText.includes('3') ? LIVE_HASH_V3 : LIVE_HASH_V1,
                    patchFingerprint: 'fp1',
                    requiresConfirmation: false,
                },
            }),
            'workspace.revision': () => ok('workspace.revision', { revisionId: 1, workspaceRevision: 1 }),
            'patch.apply': (_params) => {
                applyAttempts += 1;
                if (applyAttempts === 1) {
                    return {
                        id: 'mock:patch.apply',
                        ok: false,
                        error: {
                            code: 4004,
                            string_code: 'coherence_mismatch',
                            message: 'Anchored file content changed since this task read it.',
                            reason: 'anchored_file_changed',
                            changedPaths: [PATH],
                            requiredAction: 'refresh_context',
                            currentWorkspaceRevision: 2,
                        },
                    };
                }
                return ok('patch.apply', {
                    applied: true,
                    mutationReceipt: {
                        path: PATH,
                        beforeContentHash: LIVE_HASH_V3,
                        postContentHash: POST_HASH,
                        patchFingerprint: 'fp1',
                        readSourceBefore: 'disk',
                        applyChannel: 'disk',
                        atomic: true,
                    },
                });
            },
        });
        const result = await safePatchFile(transport, PATH, patchForValue(1, 2), {
            taskId: TASK_ID,
            idempotencyKey: 'coh-recovery',
            buildPatchFromContent: ({ content }) => {
                const match = content.match(/VALUE = (\d+)/);
                const current = match ? Number(match[1]) : 1;
                return patchForValue(current, 2);
            },
            onCoherenceEvent: (event) => events.push(event),
        });
        assert.equal(result.applied, true);
        assert.equal(applyAttempts, 2);
        assert.deepEqual(events.map((e) => e.type), ['context.stale', 'context.refreshed', 'coherence.retry']);
        assert.equal(events[0]?.type, 'context.stale');
        assert.equal(events[0]?.reason, 'anchored_file_changed');
    });
    it('returns operator intervention after a second coherence_mismatch', async () => {
        const events = [];
        const transport = new MockRpcTransport({
            'file.read': () => ok('file.read', {
                text: 'VALUE = 3\n',
                coherence: {
                    tokenId: 'coh_1',
                    workspaceRevision: 1,
                    verifyRevision: 0,
                    anchors: { [PATH]: `fnv1a:${LIVE_HASH_V3}` },
                },
            }),
            'patch.validate': () => ok('patch.validate', {
                validation: {
                    ok: true,
                    beforeContentHash: LIVE_HASH_V3,
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
                    string_code: 'coherence_mismatch',
                    message: 'stale',
                    reason: 'anchored_file_changed',
                    changedPaths: [PATH],
                },
            }),
        });
        const result = await safePatchFile(transport, PATH, patchForValue(3, 2), {
            taskId: TASK_ID,
            buildPatchFromContent: () => patchForValue(3, 2),
            onCoherenceEvent: (event) => events.push(event),
        });
        assert.equal(result.applied, false);
        if ('operatorInterventionRequired' in result) {
            assert.equal(result.operatorInterventionRequired, true);
        }
        assert.ok(events.some((e) => e.type === 'coherence.operator_required'));
        assert.equal(transport.calls.filter((c) => c.method === 'patch.apply').length, 2);
    });
    it('does not auto-retry coherence without buildPatchFromContent', async () => {
        const transport = new MockRpcTransport({
            'file.read': () => ok('file.read', {
                text: 'VALUE = 1\n',
                coherence: {
                    tokenId: 'coh_1',
                    workspaceRevision: 1,
                    verifyRevision: 0,
                    anchors: { [PATH]: `fnv1a:${LIVE_HASH_V1}` },
                },
            }),
            'patch.validate': () => ok('patch.validate', {
                validation: {
                    ok: true,
                    beforeContentHash: LIVE_HASH_V1,
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
                    string_code: 'coherence_mismatch',
                    message: 'stale',
                    reason: 'workspace_changed',
                    changedPaths: [],
                },
            }),
        });
        const result = await safePatchFile(transport, PATH, patchForValue(1, 2), {
            taskId: TASK_ID,
        });
        assert.equal(result.applied, false);
        if ('coherenceStale' in result) {
            assert.equal(result.coherenceStale, true);
            assert.equal(result.operatorInterventionRequired, false);
        }
        assert.equal(transport.calls.filter((c) => c.method === 'patch.apply').length, 1);
    });
    it('recovers when initial patch.validate fails under governed task', async () => {
        const fileText = 'VALUE = 3\n';
        const events = [];
        const transport = new MockRpcTransport({
            'patch.validate': (params) => {
                const patch = String(params.patch ?? '');
                if (patch.includes('VALUE = 1')) {
                    return ok('patch.validate', {
                        validation: { ok: false, beforeContentHash: LIVE_HASH_V3 },
                    });
                }
                return ok('patch.validate', {
                    validation: { ok: true, beforeContentHash: LIVE_HASH_V3 },
                });
            },
            'file.read': () => ok('file.read', {
                text: fileText,
                coherence: {
                    tokenId: 'coh_refresh',
                    workspaceRevision: 2,
                    verifyRevision: 0,
                    anchors: {},
                },
            }),
            'patch.apply': () => ok('patch.apply', {
                applied: true,
                mutationReceipt: {
                    path: PATH,
                    beforeContentHash: LIVE_HASH_V3,
                    postContentHash: POST_HASH,
                    patchFingerprint: 'fp1',
                    readSourceBefore: 'disk',
                    applyChannel: 'disk',
                    atomic: true,
                },
            }),
            'workspace.revision': () => ok('workspace.revision', { revisionId: 2 }),
        });
        const result = await safePatchFile(transport, PATH, patchForValue(1, 2), {
            taskId: TASK_ID,
            buildPatchFromContent: ({ content }) => patchForValue(Number(content.match(/VALUE = (\d+)/)?.[1] ?? 3), 2),
            onCoherenceEvent: (event) => events.push(event),
        });
        assert.equal(result.applied, true);
        assert.ok(events.some((e) => e.type === 'context.stale'));
        assert.ok(events.some((e) => e.type === 'coherence.retry'));
    });
    it('parses single-line replacement from unified diff', () => {
        const parsed = parseSingleLineReplacement(patchForValue(3, 2));
        assert.deepEqual(parsed, { search: 'VALUE = 3', replace: 'VALUE = 2' });
    });
});
//# sourceMappingURL=bridge.coherenceRecovery.test.js.map