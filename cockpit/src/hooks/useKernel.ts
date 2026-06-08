import { useCallback, useEffect, useRef, useState } from 'react';

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

export interface HealthBanner {
  id: string;
  severity: 'info' | 'warning' | 'error';
  message: string;
  detail?: string;
}

export interface AffectedFile {
  path: string;
  reason: string;
}

export interface WorkspaceStatus {
  contextRefreshId?: number;
  lastVerifiedCommand?: string;
  lastVerifiedAt?: string;
  driftDetected?: boolean;
  affectedFiles?: AffectedFile[];
}

export interface HealthSnapshot {
  kernelConnected: boolean;
  kernelError?: string;
  bridgeRecovered: boolean;
  workspaceDrift: boolean;
  externalChangeDetected: boolean;
  workspaceStatus?: WorkspaceStatus;
  affectedFiles?: AffectedFile[];
  expiredApprovalCount: number;
  banners: HealthBanner[];
  tasks: {
    disconnected: string[];
    awaitingApproval: string[];
    running: string[];
    queued: string[];
    verificationRequired: string[];
    verificationFailed: string[];
  };
}

export interface SessionState {
  activeTaskId?: string;
  recentDiffs?: Array<{ path: string; preview?: string; taskId?: string; timestamp: string }>;
  health?: HealthSnapshot;
  tasks?: Array<{
    taskId: string;
    status: string;
    verificationState?: string;
    error?: string;
    lastVerifyCommand?: string;
    lastVerifyOutput?: string;
    mutatedPaths?: string[];
  }>;
}

const SSE_STALE_MS = 20_000;

export function useKernel() {
  const [status, setStatus] = useState<KernelStatus>({ connected: false });
  const [events, setEvents] = useState<KernelEvent[]>([]);
  const [session, setSession] = useState<SessionState>({});
  const [health, setHealth] = useState<HealthSnapshot | null>(null);
  const [sseStale, setSseStale] = useState(false);
  const lastEventAt = useRef(Date.now());
  const sseGeneration = useRef(0);

  const applyHealth = useCallback((snapshot: HealthSnapshot | undefined) => {
    if (snapshot) setHealth(snapshot);
  }, []);

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

  const refreshHealth = useCallback(async () => {
    try {
      const res = await fetch('/api/health');
      if (!res.ok) return;
      const data = (await res.json()) as HealthSnapshot;
      applyHealth(data);
    } catch {
      // bridge unavailable
    }
  }, [applyHealth]);

  const restoreSession = useCallback(async () => {
    try {
      const res = await fetch('/api/session');
      if (!res.ok) return;
      const data = (await res.json()) as SessionState & { events?: KernelEvent[] };
      if (data.events?.length) {
        setEvents(data.events.slice(-299));
        lastEventAt.current = Date.now();
      }
      const tasks = (data as { tasks?: SessionState['tasks'] }).tasks;
      setSession({
        activeTaskId: data.activeTaskId,
        recentDiffs: data.recentDiffs,
        tasks,
      });
      applyHealth(data.health);
    } catch {
      // bridge may still be starting
    }
  }, [applyHealth]);

  const reconnect = useCallback(async () => {
    await fetch('/api/reconnect', { method: 'POST' });
    sseGeneration.current += 1;
    setSseStale(false);
    lastEventAt.current = Date.now();
    await Promise.all([refreshStatus(), refreshHealth(), restoreSession()]);
  }, [refreshHealth, refreshStatus, restoreSession]);

  const clearSession = useCallback(async () => {
    await fetch('/api/session/clear', { method: 'POST' });
    setEvents([]);
    setSession({});
    setHealth(null);
    await refreshHealth();
  }, [refreshHealth]);

  const exportSnapshot = useCallback(async (): Promise<string | null> => {
    const res = await fetch('/api/session/export', { method: 'POST' });
    if (!res.ok) return null;
    const data = (await res.json()) as { path?: string };
    return data.path ?? null;
  }, []);

  const refreshApprovals = useCallback(async () => {
    await fetch('/api/approvals/refresh', { method: 'POST' });
    await refreshHealth();
  }, [refreshHealth]);

  const retryTask = useCallback(
    async (taskId: string): Promise<string | null> => {
      const res = await fetch(`/api/tasks/${encodeURIComponent(taskId)}/retry`, { method: 'POST' });
      if (!res.ok) return null;
      const data = (await res.json()) as { task?: { taskId: string } };
      await restoreSession();
      return data.task?.taskId ?? null;
    },
    [restoreSession],
  );

  const cancelTask = useCallback(
    async (taskId: string) => {
      await fetch(`/api/tasks/${encodeURIComponent(taskId)}/cancel`, { method: 'POST' });
      await restoreSession();
    },
    [restoreSession],
  );

  const refreshWorkspaceContext = useCallback(async () => {
    await fetch('/api/workspace/refresh-anchor', { method: 'POST' });
    await refreshHealth();
  }, [refreshHealth]);

  const rerunWorkspaceVerify = useCallback(async () => {
    await fetch('/api/workspace/re-verify', { method: 'POST' });
    await refreshHealth();
  }, [refreshHealth]);

  const continueWorkspaceAnyway = useCallback(async () => {
    await fetch('/api/workspace/continue-anyway', { method: 'POST' });
    await refreshHealth();
  }, [refreshHealth]);

  const runTaskVerify = useCallback(
    async (taskId: string) => {
      await fetch(`/api/tasks/${encodeURIComponent(taskId)}/run-verify`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}',
      });
      await Promise.all([refreshHealth(), restoreSession()]);
    },
    [refreshHealth, restoreSession],
  );

  const waiveTaskVerification = useCallback(
    async (taskId: string) => {
      await fetch(`/api/tasks/${encodeURIComponent(taskId)}/waive-verification`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}',
      });
      await Promise.all([refreshHealth(), restoreSession()]);
    },
    [refreshHealth, restoreSession],
  );

  useEffect(() => {
    void refreshStatus();
    void refreshHealth();
    void restoreSession();
    const statusTimer = setInterval(() => {
      void refreshStatus();
      void refreshHealth();
    }, 5000);
    return () => clearInterval(statusTimer);
  }, [refreshHealth, refreshStatus, restoreSession]);

  useEffect(() => {
    const generation = sseGeneration.current;
    const source = new EventSource('/events');

    source.onmessage = (msg) => {
      if (generation !== sseGeneration.current) return;
      lastEventAt.current = Date.now();
      setSseStale(false);
      try {
        const event = JSON.parse(msg.data) as KernelEvent;
        setEvents((prev) => [...prev.slice(-299), event]);
      } catch {
        // ignore malformed frames
      }
    };

    source.onerror = () => {
      setSseStale(true);
    };

    const staleTimer = setInterval(() => {
      if (Date.now() - lastEventAt.current > SSE_STALE_MS && status.connected) {
        setSseStale(true);
      }
    }, 5000);

    return () => {
      source.close();
      clearInterval(staleTimer);
    };
  }, [status.connected]);

  const banners: HealthBanner[] = [
    ...(health?.banners ?? []),
    ...(sseStale
      ? [
          {
            id: 'sse_stale',
            severity: 'warning' as const,
            message: 'Live stream stale',
            detail: 'Event stream may be disconnected. Reconnect to resume live updates.',
          },
        ]
      : []),
  ];

  return {
    status,
    events,
    session,
    health,
    banners,
    sseStale,
    refreshStatus,
    refreshHealth,
    restoreSession,
    reconnect,
    clearSession,
    exportSnapshot,
    refreshApprovals,
    retryTask,
    cancelTask,
    refreshWorkspaceContext,
    rerunWorkspaceVerify,
    continueWorkspaceAnyway,
    runTaskVerify,
    waiveTaskVerification,
  };
}
