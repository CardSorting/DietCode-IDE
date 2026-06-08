import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { buildTaskCheckpoints } from './checkpoints.js';
import type { GovernedTask } from './taskRegistry.js';

function task(overrides: Partial<GovernedTask> = {}): GovernedTask {
  return {
    taskId: 'task_1',
    message: 'smoke',
    workspace: '/tmp/ws',
    mode: 'smoke',
    status: 'running',
    verificationState: 'none',
    createdAt: '2026-06-08T00:00:00Z',
    ...overrides,
  };
}

describe('buildTaskCheckpoints', () => {
  it('marks approval active while awaiting cockpit decision', () => {
    const snap = buildTaskCheckpoints(task({ status: 'awaiting_approval' }));
    assert.equal(snap.checkpoints.find((c) => c.key === 'approval')?.status, 'active');
    assert.equal(snap.canComplete, false);
  });

  it('blocks completion until verification passes', () => {
    const snap = buildTaskCheckpoints(
      task({
        status: 'verification_required',
        verificationState: 'verification_required',
        mutationCount: 1,
        mutatedPaths: ['probe.py'],
      }),
    );
    assert.equal(snap.checkpoints.find((c) => c.key === 'verification')?.status, 'active');
    assert.equal(snap.checkpoints.find((c) => c.key === 'completion')?.status, 'blocked');
    assert.equal(snap.canComplete, false);
  });

  it('allows completion only when verified', () => {
    const snap = buildTaskCheckpoints(
      task({
        status: 'completed',
        verificationState: 'verified',
        mutationCount: 1,
        mutatedPaths: ['probe.py'],
      }),
    );
    assert.equal(snap.checkpoints.find((c) => c.key === 'verification')?.status, 'passed');
    assert.equal(snap.checkpoints.find((c) => c.key === 'completion')?.status, 'passed');
    assert.equal(snap.canComplete, true);
  });
});
