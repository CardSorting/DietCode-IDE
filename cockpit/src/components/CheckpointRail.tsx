import { useEffect, useState } from 'react';

export interface CheckpointState {
  id: number;
  key: string;
  name: string;
  question: string;
  status: string;
  detail?: string;
  blocking?: boolean;
}

export interface CheckpointSnapshot {
  taskId: string;
  taskStatus: string;
  verificationState: string;
  checkpoints: CheckpointState[];
  blockingCheckpoint?: number;
  suggestedVerifyCommand?: string;
  canComplete: boolean;
}

interface Props {
  taskId?: string | null;
  refreshKey?: number;
}

function statusClass(status: string): string {
  switch (status) {
    case 'passed':
      return 'checkpoint-passed';
    case 'failed':
    case 'blocked':
      return 'checkpoint-failed';
    case 'active':
      return 'checkpoint-active';
    case 'waived':
      return 'checkpoint-waived';
    case 'skipped':
      return 'checkpoint-skipped';
    default:
      return 'checkpoint-pending';
  }
}

export function CheckpointRail({ taskId, refreshKey = 0 }: Props) {
  const [snapshot, setSnapshot] = useState<CheckpointSnapshot | null>(null);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      try {
        const url = taskId
          ? `/api/tasks/${encodeURIComponent(taskId)}/checkpoints`
          : '/api/checkpoints';
        const res = await fetch(url);
        if (!res.ok) return;
        const data = (await res.json()) as { snapshot?: CheckpointSnapshot };
        if (!cancelled && data.snapshot) setSnapshot(data.snapshot);
      } catch {
        if (!cancelled) setSnapshot(null);
      }
    };
    void load();
    const timer = setInterval(load, 4000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [taskId, refreshKey]);

  if (!snapshot) return null;

  return (
    <div className="checkpoint-rail" aria-label="Task checkpoint progress">
      <div className="checkpoint-rail-header">
        <span className="checkpoint-label">Checkpoint progress</span>
        <span className="checkpoint-task-meta">
          {snapshot.taskId} · {snapshot.taskStatus}
          {snapshot.canComplete ? ' · done' : ''}
        </span>
      </div>
      <ol className="checkpoint-steps">
        {snapshot.checkpoints.map((cp) => (
          <li
            key={cp.key}
            className={`checkpoint-step ${statusClass(cp.status)}${cp.blocking ? ' checkpoint-blocking' : ''}`}
            title={cp.question}
          >
            <span className="checkpoint-step-id">{cp.id}</span>
            <span className="checkpoint-step-name">{cp.name}</span>
            <span className="checkpoint-step-status">{cp.status}</span>
            {cp.detail ? <span className="checkpoint-step-detail">{cp.detail}</span> : null}
          </li>
        ))}
      </ol>
      {snapshot.suggestedVerifyCommand && snapshot.verificationState === 'verification_required' ? (
        <p className="checkpoint-verify-hint">
          Suggested verify: <code>{snapshot.suggestedVerifyCommand}</code>
        </p>
      ) : null}
    </div>
  );
}
