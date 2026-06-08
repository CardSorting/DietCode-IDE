import type { KernelEvent } from '../hooks/useKernel';

interface Props {
  events: KernelEvent[];
  timeline: unknown[];
}

export function TaskTimeline({ events, timeline }: Props) {
  const items = events.length > 0 ? events : timeline;

  if (!Array.isArray(items) || items.length === 0) {
    return <p className="empty">No task activity yet. Start the kernel and run an agent workflow.</p>;
  }

  return (
    <div>
      {items.slice().reverse().map((item, index) => {
        const record = item as Record<string, unknown>;
        const type = String(record.type ?? record.eventType ?? 'activity');
        const detail = String(record.detail ?? record.summary ?? JSON.stringify(record).slice(0, 120));
        const time = String(record.timestamp ?? record.recordedAt ?? '');
        const key = String(record.id ?? record.sequence ?? index);
        return (
          <div className="timeline-item" key={key}>
            <div className="type">{type}</div>
            <div>{detail}</div>
            {time ? <div className="time">{time}</div> : null}
          </div>
        );
      })}
    </div>
  );
}
