import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFile, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { after, before, describe, it } from 'node:test';

import { applyPatch, validatePatch } from '../dist/adapters/patchAdapter.js';
import { resolveAppPath } from '../dist/client/config.js';
import { DietCodeBridgeClient, mapRpcError } from '../dist/index.js';
import type { RpcCaller } from '../dist/client/RpcTransport.js';

const live = process.env.BRIDGE_LIVE === '1';
const describeLive = live ? describe : describe.skip;

describeLive('bridge.live.workflows', () => {
  let client: DietCodeBridgeClient;
  let transport: RpcCaller;
  let workspaceRoot = '';

  before(async () => {
    client = new DietCodeBridgeClient({
      startApp: false,
      appPath: resolveAppPath(),
      connectTimeoutMs: 30_000,
      requestTimeoutMs: 60_000,
    });
    await client.connect({
      startApp: false,
      connectTimeoutMs: 30_000,
      requestTimeoutMs: 60_000,
    });
    transport = (client as unknown as { transport: RpcCaller }).transport;
    workspaceRoot = client.getWorkspacePath() ?? process.cwd();
  });

  after(async () => {
    await client.close();
  });

  it('workflow A — stat, safe patch, revision bump', async () => {
    const rel = `bridge_workflow_a_${randomUUID().slice(0, 8)}.py`;
    const abs = join(workspaceRoot, rel);
    await writeFile(abs, 'value = 1\n', 'utf8');
    try {
      const stat = await client.getFileStat(rel);
      assert.ok(String(stat.result.path).endsWith(rel));
      const diff = `--- ${rel}\n+++ ${rel}\n@@ -1 +1 @@\n-value = 1\n+value = 2\n`;
      const result = await client.safePatchFile(rel, diff, {
        idempotencyKey: `bridge-a:${randomUUID()}`,
      });
      assert.equal(result.applied, true);
      if (result.applied) {
        assert.ok(result.revisionAfter! > result.revisionBefore!);
        assert.ok(String(result.mutationReceipt.path).endsWith(rel));
      }
      assert.equal(await readFile(abs, 'utf8'), 'value = 2\n');
    } finally {
      await unlink(abs).catch(() => undefined);
    }
  });

  it('workflow B — stale apply surfaces structured recovery', async () => {
    const rel = `bridge_workflow_b_${randomUUID().slice(0, 8)}.py`;
    const abs = join(workspaceRoot, rel);
    await writeFile(abs, 'stale = 1\n', 'utf8');
    try {
      const diff = `--- ${rel}\n+++ ${rel}\n@@ -1 +1 @@\n-stale = 1\n+stale = 2\n`;
      const validation = await validatePatch(transport, rel, diff);
      await writeFile(abs, 'stale = 99\n', 'utf8');
      await assert.rejects(
        () =>
          applyPatch(transport, rel, diff, validation.beforeContentHash, {
            idempotencyKey: `bridge-b-apply:${randomUUID()}`,
          }),
        (error: unknown) => {
          assert.equal((error as { code?: string }).code, 'stale_content');
          return true;
        },
      );
      const stat = await client.getFileStat(rel);
      assert.notEqual(stat.result.contentHash, validation.beforeContentHash);
    } finally {
      await unlink(abs).catch(() => undefined);
    }
  });

  it('workflow C — batch apply rolls back on stale member', async () => {
    const id = randomUUID().slice(0, 8);
    const files = [`bridge_batch_a_${id}.py`, `bridge_batch_b_${id}.py`];
    const absPaths = files.map((f) => join(workspaceRoot, f));
    try {
      for (const [idx, rel] of files.entries()) {
        await writeFile(absPaths[idx], `# ${rel}\nvalue = 1\n`, 'utf8');
      }
      await writeFile(absPaths[1], '# mutated externally\nvalue = 9\n', 'utf8');
      const patches = files.map((rel) => ({
        path: rel,
        unifiedDiff: `--- ${rel}\n+++ ${rel}\n@@ -1,2 +1,2 @@\n-# ${rel}\n+# ${rel} patched\n value = 1\n`,
      }));
      const result = await client.safePatchBatch(patches, {
        idempotencyKey: `bridge-c:${randomUUID()}`,
      });
      assert.equal(result.applied, false);
      if (!result.applied) {
        assert.equal(result.rolledBack, true);
        assert.equal(result.filesVerifiedUnchanged, true);
      }
    } finally {
      await Promise.all(absPaths.map((p) => unlink(p).catch(() => undefined)));
    }
  });

  it('workflow D — semantic disabled maps to stable bridge error', async () => {
    const envelope = await transport.call('search.semantic', { query: 'forbidden' });
    assert.equal(envelope.ok, false);
    const err = mapRpcError(envelope);
    assert.equal(err.code, 'semantic_disabled');
    assert.equal(err.nextRecommendedCommand, 'search.literal');
  });
});
