import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { safePatchFile } from '../dist/workflows/safePatchFile.js';
import { MockRpcTransport } from '../dist/client/RpcTransport.js';
import type { RpcEnvelope } from '../dist/contracts/types.js';

const PATH = 'stale_probe.py';
const DIFF = `--- stale_probe.py\n+++ stale_probe.py\n@@ -1 +1 @@\n-old\n+new\n`;
const BEFORE_HASH = 'beforehash000001';
const CURRENT_HASH = 'currenthash00001';

function ok(method: string, result: Record<string, unknown>): RpcEnvelope {
  return { id: `mock:${method}`, ok: true, result };
}

describe('bridge.staleRecovery', () => {
  it('returns structured stale recovery without blind retry', async () => {
    const transport = new MockRpcTransport({
      'patch.validate': () =>
        ok('patch.validate', {
          validation: {
            ok: true,
            beforeContentHash: BEFORE_HASH,
            patchFingerprint: 'fp1',
            requiresConfirmation: false,
          },
        }),
      'workspace.revision': () => ok('workspace.revision', { revisionId: 2 }),
      'patch.apply': () => ({
        id: 'mock:patch.apply',
        ok: false,
        error: {
          code: 4004,
          string_code: 'stale_content',
          message: 'content drifted',
          recovery_hint: 'revalidate_patch_with_patch.validate',
          nextRecommendedCommand: 'patch.validate',
        },
      }),
      'file.stat': () =>
        ok('file.stat', {
          path: PATH,
          contentHash: CURRENT_HASH,
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

    const result = await safePatchFile(transport, PATH, DIFF, { idempotencyKey: 'stale-key' });
    assert.equal(result.applied, false);
    if (!result.applied && result.stale) {
      assert.equal(result.expectedBeforeHash, BEFORE_HASH);
      assert.equal(result.currentContentHash, CURRENT_HASH);
      assert.equal(result.nextRecommendedCommand, 'patch.validate');
      assert.equal(transport.calls.filter((c) => c.method === 'patch.apply').length, 1);
    }
  });
});
