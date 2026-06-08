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

export interface SessionState {
  activeTaskId?: string;
  recentDiffs?: Array<{ path: string; preview?: string; taskId?: string; timestamp: string }>;
}

export function useKernel() {
  const [status, setStatus] = useState<KernelStatus>({ connected: false });
  const [events, setEvents] = useState<KernelEvent[]>([]);
  const [session, setSession] = useState<SessionState>({});

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

  const restoreSession = useCallback(async () => {
    try {
      const res = await fetch('/api/session');
      if (!res.ok) return;
      const data = (await res.json()) as {
        events?: KernelEvent[];
        activeTaskId?: string;
        recentDiffs?: SessionState['recentDiffs'];
      };
      if (data.events?.length) {
        setEvents(data.events.slice(-299));
      }
      setSession({
        activeTaskId: data.activeTaskId,
        recentDiffs: data.recentDiffs,
      });
    } catch {
      // bridge may still be starting
    }
  }, []);

  useEffect(() => {
    void refreshStatus();
    void restoreSession();
    const statusTimer = setInterval(() => {
      void refreshStatus();
    }, 5000);
    return () => clearInterval(statusTimer);
  }, [refreshStatus, restoreSession]);

  useEffect(() => {
    const source = new EventSource('/events');
    source.onmessage = (msg) => {
      try {
        const event = JSON.parse(msg.data) as KernelEvent;
        setEvents((prev) => [...prev.slice(-299), event]);
      } catch {
        // ignore malformed frames
      }
    };
    return () => source.close();
  }, []);

  return { status, events, session, refreshStatus, restoreSession };
}
