import { useState } from 'react';

export function ChatPanel() {
  const [message, setMessage] = useState('');
  const [history, setHistory] = useState<Array<{ role: 'user' | 'system'; text: string }>>([
    {
      role: 'system',
      text: 'Cockpit chat layer connects to agents via the kernel bridge. Wire Hermes or Agent Bridge here.',
    },
  ]);

  const send = () => {
    if (!message.trim()) return;
    setHistory((prev) => [
      ...prev,
      { role: 'user', text: message.trim() },
      {
        role: 'system',
        text: 'Agent dispatch is not wired in v0.1. Use dietcode-agent-client or Hermes plugin for now.',
      },
    ]);
    setMessage('');
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div className="panel-body" style={{ flex: 1 }}>
        {history.map((entry, i) => (
          <div className="timeline-item" key={i}>
            <div className="type">{entry.role}</div>
            <div>{entry.text}</div>
          </div>
        ))}
      </div>
      <div className="chat-input">
        <input
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && send()}
          placeholder="Describe a task for the agent…"
        />
        <button onClick={send}>Send</button>
      </div>
    </div>
  );
}
