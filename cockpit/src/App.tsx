import { ApprovalPanel } from './components/ApprovalPanel';
import { ChatPanel } from './components/ChatPanel';
import { DiffPanel } from './components/DiffPanel';
import { LogStream } from './components/LogStream';
import { StatusBanners } from './components/StatusBanners';
import { TaskTimeline } from './components/TaskTimeline';
import { useEffect, useState } from 'react';
import { useKernel } from './hooks/useKernel';

export default function App() {
  const {
    status,
    events,
    session,
    banners,
    reconnect,
    clearSession,
    exportSnapshot,
    refreshApprovals,
    retryTask,
    cancelTask,
  } = useKernel();
  const [activeTaskId, setActiveTaskId] = useState<string | null>(
    session.activeTaskId ?? null,
  );
  const [actionBusy, setActionBusy] = useState(false);

  useEffect(() => {
    if (session.activeTaskId) {
      setActiveTaskId(session.activeTaskId);
    }
  }, [session.activeTaskId]);

  const runAction = async (fn: () => Promise<void>) => {
    setActionBusy(true);
    try {
      await fn();
    } finally {
      setActionBusy(false);
    }
  };

  const activeTask = session.tasks?.find((t) => t.taskId === activeTaskId);
  const canCancel =
    activeTask &&
    (activeTask.status === 'running' ||
      activeTask.status === 'queued' ||
      activeTask.status === 'awaiting_approval');

  return (
    <div className="app">
      <header className="header">
        <div>
          <h1>DietCode Cockpit</h1>
          <p className="tagline">Live control surface — not a log warehouse</p>
        </div>
        <div>
          <span className={`status-pill ${status.connected ? 'connected' : 'disconnected'}`}>
            {status.connected ? 'Kernel connected' : 'Kernel offline'}
          </span>
          {status.workspace ? (
            <p className="tagline" style={{ textAlign: 'right', marginTop: '0.25rem' }}>
              {status.workspace}
            </p>
          ) : null}
        </div>
      </header>

      <StatusBanners
        banners={banners}
        activeTaskId={canCancel ? activeTaskId : null}
        busy={actionBusy}
        onReconnect={() => runAction(async () => reconnect())}
        onRetryTask={(taskId) =>
          runAction(async () => {
            const nextId = await retryTask(taskId);
            if (nextId) setActiveTaskId(nextId);
          })
        }
        onCancelTask={(taskId) => runAction(async () => cancelTask(taskId))}
        onClearSession={() =>
          runAction(async () => {
            await clearSession();
            setActiveTaskId(null);
          })
        }
        onExportSnapshot={() =>
          runAction(async () => {
            const path = await exportSnapshot();
            if (path) {
              // eslint-disable-next-line no-alert
              window.alert(`Session exported to:\n${path}`);
            }
          })
        }
        onRefreshApprovals={() => runAction(async () => refreshApprovals())}
      />

      <div className="layout">
        <section className="panel">
          <div className="panel-header">Chat</div>
          <ChatPanel
            workspace={status.workspace}
            kernelConnected={status.connected}
            onTaskSubmitted={setActiveTaskId}
          />
        </section>

        <section className="panel">
          <div className="panel-header">Task Timeline</div>
          <div className="panel-body">
            <TaskTimeline events={events} activeTaskId={activeTaskId} />
          </div>
          <div className="panel-header">Diffs</div>
          <div className="panel-body">
            <DiffPanel sessionDiffs={session.recentDiffs} />
          </div>
        </section>

        <section className="panel">
          <div className="panel-header">Approvals</div>
          <div className="panel-body">
            <ApprovalPanel events={events} />
          </div>
          <div className="panel-header">Logs</div>
          <div className="panel-body">
            <LogStream events={events} />
          </div>
        </section>
      </div>
    </div>
  );
}
