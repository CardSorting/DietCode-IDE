import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it } from 'node:test';
import { spawn } from 'node:child_process';
import { searchLiteral } from '../adapters/searchAdapter.js';
import { extractPartialMeta, mapRpcError, normalizeBridgeResult } from '../index.js';
import { DietCodeBridgeError } from '../contracts/BridgeError.js';
import { MockRpcTransport } from '../testing/MockRpcTransport.js';
const here = dirname(fileURLToPath(import.meta.url));
const bridgeRoot = join(here, '..', '..');
const repoRoot = join(bridgeRoot, '..');
describe('bridge.partialResults', () => {
    it('normalizes partial-success envelopes', async () => {
        const fixture = JSON.parse(await readFile(join(bridgeRoot, 'tests', 'fixtures', 'partial_search.json'), 'utf8'));
        const normalized = normalizeBridgeResult(fixture, null);
        assert.equal(normalized.complete, false);
        assert.equal(normalized.partial, true);
        assert.equal(normalized.truncated, true);
        assert.equal(normalized.fallbackUsed, true);
        assert.deepEqual(normalized.warnings, ['results_truncated']);
        assert.equal(normalized.nextRecommendedCommand, 'search.literal');
    });
    it('extractPartialMeta defaults complete to true when absent', () => {
        const meta = extractPartialMeta({});
        assert.equal(meta.complete, true);
        assert.equal(meta.partial, false);
        assert.deepEqual(meta.warnings, []);
    });
    it('maps semantic_disabled to stable bridge error', () => {
        const err = mapRpcError({
            id: '1',
            ok: false,
            error: {
                code: 4008,
                string_code: 'semantic_disabled',
                message: 'semantic search disabled',
                recovery_hint: 'use_search_literal_or_search_tokens',
                nextRecommendedCommand: 'search.literal',
            },
        });
        assert.equal(err.code, 'semantic_disabled');
        assert.equal(err.nextRecommendedCommand, 'search.literal');
        assert.equal(err.retrySafe, false);
        assert.ok(err instanceof DietCodeBridgeError);
    });
    it('search adapter preserves partial metadata', async () => {
        const fixture = JSON.parse(await readFile(join(bridgeRoot, 'tests', 'fixtures', 'partial_search.json'), 'utf8'));
        const transport = new MockRpcTransport({
            'search.literal': () => ({ id: 'mock', ok: true, result: fixture }),
        });
        const result = await searchLiteral(transport, 'anchor');
        assert.equal(result.partial, true);
        assert.equal(result.truncated, true);
    });
    it('CLI emits compact JSON by default', async () => {
        const cli = join(bridgeRoot, 'dist', 'cli', 'dietcode-agent-client.js');
        const completed = await new Promise((resolve) => {
            const child = spawn('node', [cli, '--no-start', 'verify', 'fast'], {
                cwd: repoRoot,
                env: { ...process.env, DIETCODE_APP_PATH: '' },
            });
            let stdout = '';
            let stderr = '';
            child.stdout.on('data', (chunk) => {
                stdout += String(chunk);
            });
            child.stderr.on('data', (chunk) => {
                stderr += String(chunk);
            });
            child.on('close', () => resolve({ stdout, stderr }));
        });
        const payload = (completed.stdout || completed.stderr).trim();
        assert.notEqual(payload, '');
        const parsed = JSON.parse(payload.split('\n').at(-1) ?? payload);
        assert.ok('ok' in parsed || 'error' in parsed);
        if ('latencyMs' in parsed || (parsed.error && parsed.ok === false)) {
            assert.equal(payload.includes('\n  '), false, 'default output must be compact JSON');
        }
    });
});
//# sourceMappingURL=bridge.partialResults.test.js.map