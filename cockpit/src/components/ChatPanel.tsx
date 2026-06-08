import { useCallback, useState } from 'react';

interface Props {
  workspace?: string;
  onTaskSubmitted?: (taskId: string) => void;
}

export function ChatPanel({ workspace, onTaskSubmitted }: Props) {
  const [message, setMessage] = useState('');
  const [mode, setMode] = useState<'supervised' | 'trusted'>('supervised');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastTaskId, setLastTaskId] = useState<string | null>(null);

  const submitTask = useCallback(async () => {
    if (!message.trim() || busy) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch('/api/tasks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: message.trim(),
          workspace: workspace || undefined,
          mode,
        }),
      });
      const data = (await res.json()) as {
        task?: { taskId: string };
        error?: string;
      };
      if (!res.ok) {
        throw new Error(data.error ?? 'Failed to submit task');
      }
      const taskId = data.task?.taskId ?? null;
      setLastTaskId(taskId);
      setMessage('');
      if (taskId) onTaskSubmitted?.(taskId);
    } catch (err) {
      setError(String(err));
    } finally {
      setBusy(false);
    }
  }, [busy, message, mode, onTaskSubmitted, workspace]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div className="panel-body" style={{ flex: 1 }}>
        <p className="empty" style={{ marginTop: 0 }}>
          Submit a governed Hermes task. Mutations route through the kernel; destructive changes
          queue in Approvals when mode is supervised.
        </p>
        {lastTaskId ? (
          <div className="timeline-item">
            <div className="type">active task</div>
            <div>{lastTaskId}</div>
          </div>
        ) : null}
        {error ? <p className="approval-error">{error}</p> : null}
      </div>
      <div className="chat-mode">
        <label>
          <input
            type="radio"
            checked={mode === 'supervised'}
            onChange={() => setMode('supervised')}
          />
          Supervised
        </label>
        <label>
          <input
            type="radio"
            checked={mode === 'trusted'}
            onChange={() => setMode('trusted')}
          />
          Trusted
        </label>
      </div>
      <div className="chat-input">
        <input
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && void submitTask()}
          placeholder="Fix the failing test…"
          disabled={busy}
        />
        <button onClick={() => void submitTask()} disabled={busy || !message.trim()}>
          {busy ? 'Running…' : 'Run task'}
        </button>
      </div>
    </div>
  );
}
