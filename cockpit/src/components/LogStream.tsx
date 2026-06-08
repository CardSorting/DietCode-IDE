import type { KernelEvent } from '../hooks/useKernel';

interface Props {
  events: KernelEvent[];
}

export function LogStream({ events }: Props) {
  const logs = events.filter(
    (e) =>
      e.type.includes('terminal') ||
      e.type.includes('shell') ||
      e.type.includes('verify') ||
      e.type.includes('log'),
  );

  const items = logs.length > 0 ? logs : events.slice(-20);

  if (items.length === 0) {
    return <p className="empty">Kernel logs will stream here via event.subscribe.</p>;
  }

  return (
    <div>
      {items.slice().reverse().map((item) => (
        <div className="log-line" key={item.id}>
          <span className="time">{item.timestamp} </span>
          <strong>{item.type}</strong> {item.detail}
        </div>
      ))}
    </div>
  );
}
