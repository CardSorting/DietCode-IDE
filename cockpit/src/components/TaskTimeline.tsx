import type { KernelEvent } from '../hooks/useKernel';

const TASK_EVENT_TYPES = new Set([
  'task.started',
  'task.completed',
  'task.failed',
  'task.disconnected',
  'agent.message',
  'tool.call.started',
  'tool.call.completed',
  'approval.required',
  'approval.resolved',
  'file.diff',
  'verify.started',
  'verify.completed',
  'verify.complete',
]);

interface Props {
  events: KernelEvent[];
  activeTaskId?: string | null;
}

function formatDetail(event: KernelEvent): string {
  const payload = event.payload ?? {};
  if (event.type === 'agent.message') {
    const text = String(payload.text ?? event.detail ?? '');
    return text.length > 300 ? `${text.slice(0, 300)}…` : text;
  }
  if (event.type === 'tool.call.started' || event.type === 'tool.call.completed') {
    return String(payload.action ?? event.detail);
  }
  if (event.type === 'approval.required' || event.type === 'approval.resolved') {
    const approvalId =
      (payload.approvalId as string | undefined) ||
      ((payload.approval as Record<string, unknown> | undefined)?.approvalId as string | undefined);
    return approvalId ? `${event.detail} (${approvalId})` : event.detail;
  }
  if (event.type === 'file.diff') {
    return String(payload.path ?? event.detail);
  }
  return event.detail || JSON.stringify(payload).slice(0, 160);
}

export function TaskTimeline({ events, activeTaskId }: Props) {
  const taskEvents = events.filter((event) => {
    if (!TASK_EVENT_TYPES.has(event.type)) return false;
    if (!activeTaskId) return true;
    const taskId =
      event.taskId ||
      (event.payload?.taskId as string | undefined) ||
      (event.payload?.approval as Record<string, unknown> | undefined)?.taskId;
    return !taskId || taskId === activeTaskId;
  });

  if (taskEvents.length === 0) {
    return (
      <p className="empty">
        No governed task activity yet. Submit a task from Chat — events stream here in real time.
      </p>
    );
  }

  return (
    <div className="task-timeline">
      {taskEvents
        .slice()
        .reverse()
        .map((event) => (
          <div className={`timeline-item event-${event.type.replace(/\./g, '-')}`} key={event.id}>
            <div className="timeline-meta">
              <span className="type">{event.type}</span>
              {event.taskId ? <span className="task-tag">{event.taskId}</span> : null}
            </div>
            <div>{formatDetail(event)}</div>
            <div className="time">{event.timestamp}</div>
          </div>
        ))}
    </div>
  );
}
