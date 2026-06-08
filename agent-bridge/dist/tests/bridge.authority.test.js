import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { mapRpcError as mapRpcErrorFromErrors } from '../contracts/errors.js';
import { DietCodeBridgeError, resolveBridgeRecovery } from '../contracts/BridgeError.js';
describe('bridge.authority.recovery', () => {
    it('runtime hint wins over bridge default', () => {
        const err = mapRpcErrorFromErrors({
            id: '1',
            ok: false,
            error: {
                code: 4004,
                string_code: 'stale_content',
                message: 'content drifted',
                recovery_hint: 'runtime_custom_hint',
                nextRecommendedCommand: 'patch.validate',
                retryable: false,
            },
        });
        assert.equal(err.recoveryHint, 'runtime_custom_hint');
        assert.equal(err.recoverySource, 'runtime');
        assert.equal(err.nextCommandSource, 'runtime');
        assert.ok(err.rawError);
    });
    it('uses bridge fallback only when runtime hints are absent', () => {
        const err = mapRpcErrorFromErrors({
            id: '2',
            ok: false,
            error: {
                code: 4008,
                string_code: 'semantic_disabled',
                message: 'semantic disabled',
            },
        });
        assert.equal(err.recoveryHint, 'use_search_literal_or_search_tokens');
        assert.equal(err.recoverySource, 'bridge_fallback');
        assert.equal(err.nextCommandSource, 'bridge_fallback');
    });
    it('never rewrites protected runtime recovery paths when runtime hints present', () => {
        for (const code of ['stale_content', 'symlink_target', 'patch_failed', 'semantic_disabled']) {
            const resolved = resolveBridgeRecovery(code, {
                recovery_hint: `runtime_hint_for_${code}`,
                nextRecommendedCommand: 'runtime.next',
            });
            assert.equal(resolved.recoveryHint, `runtime_hint_for_${code}`);
            assert.equal(resolved.recoverySource, 'runtime');
            assert.equal(resolved.nextRecommendedCommand, 'runtime.next');
        }
    });
    it('includes rawError in thrown bridge errors', () => {
        const payload = {
            code: 4004,
            string_code: 'patch_failed',
            message: 'patch failed',
            recovery_hint: 'run_patch_preview_or_patch_validate',
            nextRecommendedCommand: 'patch.validate',
        };
        const err = mapRpcErrorFromErrors({ id: '3', ok: false, error: payload });
        assert.deepEqual(err.rawError, payload);
        assert.equal(err.toJSON().recoverySource, 'runtime');
    });
    it('does not mark unknown codes as runtime-sourced without hints', () => {
        const err = mapRpcErrorFromErrors({
            id: '4',
            ok: false,
            error: { code: -32000, string_code: 'unknown_thing', message: 'fail' },
        });
        assert.equal(err.code, 'unknown');
        assert.equal(err.recoverySource, 'bridge_fallback');
    });
    it('bridge fallback for nested_call_timeout when runtime omits hints', () => {
        const err = new DietCodeBridgeError('nested_call_timeout', 'timed out');
        assert.equal(err.recoveryHint, 'reduce_concurrency_or_retry_later');
        assert.equal(err.recoverySource, 'bridge_fallback');
        assert.equal(err.retrySafe, true);
    });
});
//# sourceMappingURL=bridge.authority.test.js.map