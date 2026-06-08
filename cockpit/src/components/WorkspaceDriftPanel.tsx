export interface AffectedFile {
  path: string;
  reason: string;
}

interface Props {
  affectedFiles: AffectedFile[];
  activeTaskId?: string | null;
  busy?: boolean;
  onRefreshContext: () => void;
  onCancelTask?: (taskId: string) => void;
  onContinueAnyway: () => void;
}

export function WorkspaceDriftPanel({
  affectedFiles,
  activeTaskId,
  busy,
  onRefreshContext,
  onCancelTask,
  onContinueAnyway,
}: Props) {
  if (affectedFiles.length === 0) return null;

  return (
    <div className="workspace-drift-panel severity-warning">
      <div className="workspace-drift-header">
        <span className="checkpoint-label">Checkpoint 2 · Drift</span>
        <strong>Workspace changed outside DietCode</strong>
        <p className="tagline">Did the workspace change underneath the agent? Refresh context before mutation.</p>
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

      <div className="workspace-drift-actions">
        <button type="button" disabled={busy} onClick={() => void onRefreshContext()}>
          Refresh context
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
