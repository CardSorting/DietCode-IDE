export interface AffectedFile {
  path: string;
  reason: string;
}

interface Props {
  affectedFiles: AffectedFile[];
  lastVerifiedCommand?: string;
  lastVerifiedAt?: string;
  activeTaskId?: string | null;
  busy?: boolean;
  onRefreshContext: () => void;
  onRerunVerify: () => void;
  onCancelTask?: (taskId: string) => void;
  onContinueAnyway: () => void;
}

export function WorkspaceDriftPanel({
  affectedFiles,
  lastVerifiedCommand,
  lastVerifiedAt,
  activeTaskId,
  busy,
  onRefreshContext,
  onRerunVerify,
  onCancelTask,
  onContinueAnyway,
}: Props) {
  if (affectedFiles.length === 0) return null;

  return (
    <div className="workspace-drift-panel severity-warning">
      <div className="workspace-drift-header">
        <strong>Workspace changed outside DietCode</strong>
        <p className="tagline">State validity check — refresh context before the agent mutates.</p>
      </div>

      <div className="workspace-drift-files">
        <span className="workspace-drift-label">Affected files:</span>
        <ul>
          {affectedFiles.map((file) => (
            <li key={`${file.path}:${file.reason}`}>
              <code>{file.path}</code> — {file.reason}
            </li>
          ))}
        </ul>
      </div>

      {lastVerifiedCommand ? (
        <p className="workspace-drift-verify-meta">
          Last verified: <code>{lastVerifiedCommand}</code>
          {lastVerifiedAt ? ` at ${lastVerifiedAt}` : null}
        </p>
      ) : null}

      <div className="workspace-drift-actions">
        <button type="button" disabled={busy} onClick={() => void onRefreshContext()}>
          Refresh context
        </button>
        <button type="button" disabled={busy || !lastVerifiedCommand} onClick={() => void onRerunVerify()}>
          Re-run verify
        </button>
        {activeTaskId && onCancelTask ? (
          <button type="button" disabled={busy} onClick={() => void onCancelTask(activeTaskId)}>
            Cancel task
          </button>
        ) : null}
        <button type="button" className="muted" disabled={busy} onClick={() => void onContinueAnyway()}>
          Continue anyway
        </button>
      </div>
    </div>
  );
}
