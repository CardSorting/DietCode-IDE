import { useCallback, useEffect, useState } from 'react';
import type { KernelEvent } from '../hooks/useKernel';

export interface PendingApproval {
  approvalId: string;
  taskId?: string;
  actionType?: string;
  method?: string;
  reason?: string;
  caller?: string;
  status: string;
  preview?: {
    path?: string;
    patch?: string;
    command?: string;
    method?: string;
    message?: string;
    patchCount?: number;
  };
  createdAt?: string;
  resolvedAt?: string;
  decision?: string;
  resolvedBy?: string;
  resolveReason?: string;
  executionError?: string;
}

interface Props {
  events: KernelEvent[];
}

async function fetchApprovals(status?: string): Promise<PendingApproval[]> {
  const query = status ? `?status=${encodeURIComponent(status)}` : '';
  const res = await fetch(`/api/approvals${query}`);
  if (!res.ok) return [];
  const data = (await res.json()) as { approvals?: PendingApproval[] };
  return data.approvals ?? [];
}

async function resolveApproval(
  approvalId: string,
  decision: 'approved' | 'rejected',
  reason: string,
): Promise<void> {
  const res = await fetch(`/api/approvals/${encodeURIComponent(approvalId)}/resolve`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ decision, reason, resolvedBy: 'cockpit' }),
  });
  if (!res.ok) {
    const data = (await res.json()) as { error?: string };
    throw new Error(data.error ?? 'Failed to resolve approval');
  }
}

function PreviewBlock({ approval }: { approval: PendingApproval }) {
  const preview = approval.preview;
  if (!preview) return null;

  return (
    <div className="approval-preview">
      {preview.path ? <div className="approval-path">{preview.path}</div> : null}
      {preview.command ? (
        <pre className="approval-diff">{preview.command}</pre>
      ) : null}
      {preview.patch ? (
        <pre className="approval-diff">{preview.patch}</pre>
      ) : null}
      {preview.method ? (
        <div className="approval-meta">RPC: {preview.method}</div>
      ) : null}
    </div>
  );
}

export function ApprovalPanel({ events }: Props) {
  const [pending, setPending] = useState<PendingApproval[]>([]);
  const [resolved, setResolved] = useState<PendingApproval[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const [pendingItems, resolvedItems] = await Promise.all([
        fetchApprovals('pending'),
        fetchApprovals(''),
      ]);
      setPending(pendingItems);
      setResolved(
        resolvedItems.filter((item) => item.status !== 'pending').slice(0, 20),
      );
      setError(null);
    } catch (err) {
      setError(String(err));
    }
  }, []);

  useEffect(() => {
    void refresh();
    const timer = setInterval(() => {
      void refresh();
    }, 3000);
    return () => clearInterval(timer);
  }, [refresh]);

  useEffect(() => {
    const touched = events.some(
      (e) => e.type === 'approval.required' || e.type === 'approval.resolved',
    );
    if (touched) void refresh();
  }, [events, refresh]);

  const handleResolve = async (
    approvalId: string,
    decision: 'approved' | 'rejected',
  ) => {
    setBusyId(approvalId);
    setError(null);
    try {
      await resolveApproval(
        approvalId,
        decision,
        decision === 'approved'
          ? 'User approved from cockpit'
          : 'User rejected from cockpit',
      );
      await refresh();
    } catch (err) {
      setError(String(err));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div className="approval-panel">
      <div className="approval-panel-toolbar">
        <span className="checkpoint-label">Checkpoint 3 · Approval</span>
        <button type="button" className="approval-refresh" onClick={() => void refresh()}>
          Refresh
        </button>
      </div>
      {error ? <p className="approval-error">{error}</p> : null}

      <div className="approval-section">
        <div className="approval-section-title">Pending</div>
        {pending.length === 0 ? (
          <p className="empty">
            No pending approvals. Destructive mutations queue here in supervised mode.
          </p>
        ) : (
          pending.map((item) => (
            <div className="approval-item" key={item.approvalId}>
              <div className="approval-header">
                <span className="approval-id">{item.approvalId}</span>
                <span className="approval-type">{item.actionType ?? item.method}</span>
              </div>
              <div className="approval-reason">{item.reason}</div>
              {item.taskId ? (
                <div className="approval-meta">Task: {item.taskId}</div>
              ) : null}
              <PreviewBlock approval={item} />
              <div className="approval-actions">
                <button
                  className="approve"
                  disabled={busyId === item.approvalId}
                  onClick={() => void handleResolve(item.approvalId, 'approved')}
                >
                  Approve
                </button>
                <button
                  className="reject"
                  disabled={busyId === item.approvalId}
                  onClick={() => void handleResolve(item.approvalId, 'rejected')}
                >
                  Reject
                </button>
              </div>
              <div className="time">{item.createdAt}</div>
            </div>
          ))
        )}
      </div>

      <div className="approval-section">
        <div className="approval-section-title">Resolved</div>
        {resolved.length === 0 ? (
          <p className="empty">No resolved approvals yet.</p>
        ) : (
          resolved.map((item) => (
            <div className="approval-item resolved" key={`${item.approvalId}-${item.resolvedAt}`}>
              <div className="approval-header">
                <span className="approval-id">{item.approvalId}</span>
                <span className={`approval-status ${item.status}`}>{item.status}</span>
              </div>
              <div className="approval-meta">
                {item.decision ?? item.status}
                {item.resolvedBy ? ` · ${item.resolvedBy}` : ''}
              </div>
              {item.executionError ? (
                <div className="approval-error">{item.executionError}</div>
              ) : null}
              <div className="time">{item.resolvedAt ?? item.createdAt}</div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}
