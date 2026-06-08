import { useState } from 'react';
import type { KernelEvent } from '../hooks/useKernel';

interface Props {
  events: KernelEvent[];
}

export function ApprovalQueue({ events }: Props) {
  const [resolved, setResolved] = useState<Set<string>>(new Set());

  const pending = events.filter(
    (e) =>
      (e.type.includes('approval') || e.type.includes('destructive')) &&
      !resolved.has(e.id),
  );

  if (pending.length === 0) {
    return (
      <p className="empty">
        No pending approvals. Destructive mutations in supervised mode will queue here.
      </p>
    );
  }

  return (
    <div>
      {pending.map((item) => (
        <div className="approval-item" key={item.id}>
          <div className="type">{item.type}</div>
          <div>{item.detail}</div>
          <div className="time">{item.timestamp}</div>
          <button
            className="approve"
            onClick={() => setResolved((prev) => new Set(prev).add(item.id))}
          >
            Approve
          </button>
          <button onClick={() => setResolved((prev) => new Set(prev).add(item.id))}>
            Reject
          </button>
        </div>
      ))}
    </div>
  );
}
