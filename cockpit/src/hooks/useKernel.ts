import { useCallback, useEffect, useState } from 'react';

export interface KernelEvent {
  id: string;
  sequence: number;
  timestamp: string;
  type: string;
  source: string;
  detail: string;
  payload?: Record<string, unknown>;
  taskId?: string;
}

export interface KernelStatus {
  connected: boolean;
  workspace?: string;
  version?: string;
  error?: string;
}

export function useKernel() {
  const [status, setStatus] = useState<KernelStatus>({ connected: false });
  const [events, setEvents] = useState<KernelEvent[]>([]);
  const [timeline, setTimeline] = useState<unknown[]>([]);

  const refreshStatus = useCallback(async () => {
    try {
      const res = await fetch('/api/status');
      const data = (await res.json()) as {
        connected: boolean;
        ping?: { version?: string };
        workspace?: { root?: string };
        error?: string;
      };
      setStatus({
        connected: data.connected,
        workspace: data.workspace?.root,
        version: data.ping?.version,
        error: data.error,
      });
    } catch (err) {
      setStatus({ connected: false, error: String(err) });
    }
  }, []);

  const refreshTimeline = useCallback(async () => {
    try {
      const res = await fetch('/api/rpc', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ method: 'runtime.timeline', params: { limit: 30, compact: true } }),
      });
      const data = (await res.json()) as { result?: { events?: unknown[] } };
      setTimeline(data.result?.events ?? []);
    } catch {
      setTimeline([]);
    }
  }, []);

  useEffect(() => {
    void refreshStatus();
    void refreshTimeline();
    const statusTimer = setInterval(() => {
      void refreshStatus();
    }, 5000);
    const timelineTimer = setInterval(() => {
      void refreshTimeline();
    }, 10000);
    return () => {
      clearInterval(statusTimer);
      clearInterval(timelineTimer);
    };
  }, [refreshStatus, refreshTimeline]);

  useEffect(() => {
    const source = new EventSource('/events');
    source.onmessage = (msg) => {
      try {
        const event = JSON.parse(msg.data) as KernelEvent;
        setEvents((prev) => [...prev.slice(-199), event]);
      } catch {
        // ignore malformed frames
      }
    };
    return () => source.close();
  }, []);

  return { status, events, timeline, refreshStatus, refreshTimeline };
}
