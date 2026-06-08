import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, describe, it } from 'node:test';

import { resolveAppPath } from '../dist/client/config.js';
import { DietCodeBridgeClient } from '../dist/index.js';

const live = process.env.BRIDGE_LIVE === '1';
const describeLive = live ? describe : describe.skip;

describeLive('bridge.live', () => {
  let client: DietCodeBridgeClient;

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
  });

  after(async () => {
    await client.close();
  });

  it('connects and exposes a complete runtime profile', () => {
    const profile = client.getRuntimeProfile();
    assert.equal(profile.connected, true);
    assert.equal(profile.capabilities.deterministicSearch, true);
    assert.equal(profile.capabilities.patchReceipts, true);
    assert.equal(profile.capabilities.batchReceipts, true);
    assert.equal(profile.capabilities.runtimeTimeline, true);
    assert.equal(profile.capabilities.broccoliqJournal, true);
    assert.equal(profile.capabilities.operationStatus, true);
    assert.equal(profile.capabilities.partialSuccessEnvelopes, true);
    assert.equal(profile.semanticSearchDisabled, true);
    assert.equal(profile.diagnosticsAvailable, true);
    assert.ok(profile.mutationAuthority);
    assert.ok(profile.recordAuthority);
    assert.ok(client.getWorkspacePath());
  });

  it('returns normalized diagnostics without raw by default', async () => {
    const diagnostics = await client.getDiagnostics();
    assert.equal(diagnostics.complete, true);
    assert.equal(diagnostics.partial, false);
    assert.ok(diagnostics.result);
    assert.equal(diagnostics.result.available, true);
    assert.equal('raw' in diagnostics, false);
  });

  it('performs deterministic literal search', async () => {
    const result = await client.searchLiteral('DietCodeBridgeClient', {
      maxResults: 5,
      include: ['agent-bridge/src/client/DietCodeBridgeClient.ts'],
    });
    assert.ok(result.result);
    assert.equal(result.result.agentSafe, true);
    assert.equal(result.result.rankingPolicy, 'none');
  });

  it('performs deterministic path search for the bridge package', async () => {
    const result = await client.searchPaths('agent-bridge', { maxResults: 10 });
    assert.ok(result.result);
    assert.equal(result.result.searchMode, 'deterministic_path_match');
  });

  it('reads file stat through the bridge adapter', async () => {
    const stat = await client.getFileStat('agent-bridge/package.json');
    assert.equal(stat.complete, true);
    assert.ok(stat.result);
    assert.ok(String(stat.result.path).endsWith('agent-bridge/package.json'));
  });

  it('returns runtime timeline and recent activity envelopes', async () => {
    const timeline = await client.getTimeline({ limit: 5 });
    assert.ok(timeline.result);
    assert.equal(timeline.result.sortOrder, 'timestamp_desc');
    assert.ok(Array.isArray(timeline.result.events));

    const activity = await client.getRecentActivity({ limit: 5 });
    assert.ok(activity.result);
    assert.equal(activity.result.mode, 'runtime_timeline');
    assert.ok(Array.isArray(activity.result.events));
  });

  it('verifyFast reports a healthy live runtime', async () => {
    const verify = await client.verifyFast();
    assert.equal(verify.ok, true);
    assert.equal(verify.rpcReady, true);
    assert.equal(verify.runtimeAvailable, true);
    assert.ok(verify.latencyMs >= 0);
  });

  it('surfaces operation.status for unknown idempotency keys', async () => {
    const status = await client.getOperationStatus(`bridge-live-missing:${randomUUID()}`);
    assert.ok(status.idempotencyKey.startsWith('bridge-live-missing:'));
    assert.ok(['unknown', 'not_found', 'pending', 'completed', 'failed'].includes(status.status));
  });
});
