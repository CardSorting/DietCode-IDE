import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it } from 'node:test';

import {
  assertRequiredCapabilities,
  detectRuntimeCapabilities,
  unsupportedCapabilityError,
} from '../dist/index.js';
import { MockRpcTransport } from '../dist/client/RpcTransport.js';
import type { RpcEnvelope } from '../dist/contracts/types.js';

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = join(here, '..', '..', 'tests', 'fixtures');

async function loadFixture(name: string): Promise<Record<string, unknown>> {
  const text = await readFile(join(fixtures, name), 'utf8');
  return JSON.parse(text) as Record<string, unknown>;
}

function ok(method: string, result: Record<string, unknown>): RpcEnvelope {
  return { id: `mock:${method}`, ok: true, result };
}

describe('bridge.capabilities', () => {
  it('detects required capabilities from runtime surfaces', async () => {
    const capabilities = await loadFixture('capabilities_ok.json');
    const diagnostics = await loadFixture('diagnostics_ok.json');
    const transport = new MockRpcTransport({
      'tool.capabilities': () => ok('tool.capabilities', capabilities),
      'runtime.diagnostics': () => ok('runtime.diagnostics', diagnostics),
    });

    const profile = await detectRuntimeCapabilities(transport);
    assert.equal(profile.capabilities.deterministicSearch, true);
    assert.equal(profile.capabilities.patchReceipts, true);
    assert.equal(profile.capabilities.batchReceipts, true);
    assert.equal(profile.capabilities.broccoliqJournal, true);
    assert.equal(profile.semanticSearchDisabled, true);
  });

  it('fails loudly when required features are missing', async () => {
    const capabilities = await loadFixture('capabilities_missing.json');
    const diagnostics = await loadFixture('diagnostics_ok.json');
    const transport = new MockRpcTransport({
      'tool.capabilities': () => ok('tool.capabilities', capabilities),
      'runtime.diagnostics': () => ok('runtime.diagnostics', diagnostics),
    });

    await assert.rejects(
      () => detectRuntimeCapabilities(transport),
      (error: unknown) => {
        assert.equal((error as { code: string }).code, 'unsupported_runtime_capability');
        return true;
      },
    );
  });

  it('assertRequiredCapabilities throws for partial capability set', () => {
    assert.throws(() =>
      assertRequiredCapabilities({
        deterministicSearch: true,
        patchReceipts: false,
        batchReceipts: false,
        runtimeTimeline: false,
        broccoliqJournal: false,
        operationStatus: false,
        partialSuccessEnvelopes: false,
      }),
    );
  });

  it('unsupportedCapabilityError includes recovery metadata', () => {
    const err = unsupportedCapabilityError('patch receipts', 'patch.apply missing');
    assert.equal(err.code, 'unsupported_runtime_capability');
    assert.ok(err.recoveryHint);
    assert.ok(err.nextRecommendedCommand);
  });
});
