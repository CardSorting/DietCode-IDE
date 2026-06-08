import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  getSessionRecentDiffs,
  nextSessionTaskId,
  recordSessionEvent,
} from './sessionStore.js';

describe('sessionStore', () => {
  it('issues monotonic task ids', () => {
    const first = nextSessionTaskId();
    const second = nextSessionTaskId();
    assert.match(first, /^task_\d+$/);
    assert.match(second, /^task_\d+$/);
    assert.notEqual(first, second);
  });

  it('records workspace.mutated paths in the diff ring', () => {
    const before = getSessionRecentDiffs().length;
    recordSessionEvent({
      id: 'unit-mut-1',
      sequence: 2_000_001,
      timestamp: '2026-06-08T00:00:00Z',
      type: 'workspace.mutated',
      source: 'test',
      detail: 'mutated probe.py',
      payload: { changedPaths: ['probe.py'], method: 'patch.apply' },
      taskId: 'task_unit',
    });
    const diffs = getSessionRecentDiffs();
    assert.ok(diffs.length >= before + 1);
    assert.equal(diffs[0]?.path, 'probe.py');
    assert.equal(diffs[0]?.taskId, 'task_unit');
  });
});
