import { ApprovalPanel } from './components/ApprovalPanel';
import { ChatPanel } from './components/ChatPanel';
import { DiffPanel } from './components/DiffPanel';
import { LogStream } from './components/LogStream';
import { StatusBanners } from './components/StatusBanners';
import { WorkspaceDriftPanel } from './components/WorkspaceDriftPanel';
import { VerifyGatePanel } from './components/VerifyGatePanel';
import { CheckpointRail } from './components/CheckpointRail';
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
    refreshWorkspaceContext,
    continueWorkspaceAnyway,
    runTaskVerify,
    waiveTaskVerification,
    health,
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
      activeTask.status === 'awaiting_approval' ||
      activeTask.status === 'verification_required' ||
      activeTask.status === 'verification_failed');

  const verifyGateTask =
    activeTask &&
    (activeTask.status === 'verification_required' ||
      activeTask.status === 'verification_failed' ||
      activeTask.verificationState === 'verification_required' ||
      activeTask.verificationState === 'verification_failed')
      ? activeTask
      : session.tasks?.find(
          (t) =>
            t.status === 'verification_required' || t.status === 'verification_failed',
        );

  return (
    <div className="app">
      <header className="header">
        <div>
          <h1>DietCode Cockpit</h1>
          <p className="tagline">Bounded autonomy through visible checkpoints</p>
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

      <CheckpointRail taskId={activeTaskId} refreshKey={events.length} />

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

      {(health?.workspaceDrift ||
        (health?.affectedFiles?.length ?? 0) > 0 ||
        (health?.workspaceStatus?.affectedFiles?.length ?? 0) > 0) && (
      <WorkspaceDriftPanel
        affectedFiles={
          health?.affectedFiles ??
          health?.workspaceStatus?.affectedFiles ?? [
            { path: '(workspace)', reason: 'changed outside DietCode' },
          ]
        }
        activeTaskId={canCancel ? activeTaskId : null}
        busy={actionBusy}
        onRefreshContext={() => runAction(async () => refreshWorkspaceContext())}
        onCancelTask={(taskId) => runAction(async () => cancelTask(taskId))}
        onContinueAnyway={() => runAction(async () => continueWorkspaceAnyway())}
      />
      )}

      {verifyGateTask ? (
        <VerifyGatePanel
          taskId={verifyGateTask.taskId}
          status={verifyGateTask.status}
          verificationState={verifyGateTask.verificationState}
          lastVerifyCommand={verifyGateTask.lastVerifyCommand}
          lastVerifyOutput={verifyGateTask.lastVerifyOutput}
          mutatedPaths={verifyGateTask.mutatedPaths}
          busy={actionBusy}
          onRunVerify={(taskId) => runAction(async () => runTaskVerify(taskId))}
          onRetryTask={(taskId) =>
            runAction(async () => {
              const nextId = await retryTask(taskId);
              if (nextId) setActiveTaskId(nextId);
            })
          }
          onWaiveVerification={(taskId) => runAction(async () => waiveTaskVerification(taskId))}
          onCancelTask={(taskId) => runAction(async () => cancelTask(taskId))}
        />
      ) : null}

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
          <div className="panel-header">Timeline</div>
          <p className="panel-subheader">Cross-checkpoint audit trail (not a gate)</p>
          <div className="panel-body">
            <TaskTimeline events={events} activeTaskId={activeTaskId} />
          </div>
          <div className="panel-header">Checkpoint 4 · Mutation</div>
          <p className="panel-subheader">Diffs</p>
          <div className="panel-body">
            <DiffPanel sessionDiffs={session.recentDiffs} />
          </div>
        </section>

        <section className="panel">
          <div className="panel-header">Checkpoint 3 · Approval</div>
          <div className="panel-body">
            <ApprovalPanel events={events} />
          </div>
          <div className="panel-header">Debug log</div>
          <p className="panel-subheader">Raw kernel stream — not a checkpoint</p>
          <div className="panel-body">
            <LogStream events={events} />
          </div>
        </section>
      </div>
    </div>
  );
}
