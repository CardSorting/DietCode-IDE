import { useState } from 'react';

interface Props {
  taskId: string;
  status: string;
  verificationState?: string;
  lastVerifyCommand?: string;
  lastVerifyOutput?: string;
  mutatedPaths?: string[];
  busy?: boolean;
  onRunVerify: (taskId: string) => void;
  onRetryTask: (taskId: string) => void;
  onWaiveVerification: (taskId: string) => void;
  onCancelTask: (taskId: string) => void;
}

export function VerifyGatePanel({
  taskId,
  status,
  verificationState,
  lastVerifyCommand,
  lastVerifyOutput,
  mutatedPaths,
  busy,
  onRunVerify,
  onRetryTask,
  onWaiveVerification,
  onCancelTask,
}: Props) {
  const [showOutput, setShowOutput] = useState(false);

  const pending =
    status === 'verification_required' || verificationState === 'verification_required';
  const failed = status === 'verification_failed' || verificationState === 'verification_failed';

  if (!pending && !failed) return null;

  return (
    <div className={`verify-gate-panel severity-${failed ? 'error' : 'warning'}`}>
      <div className="verify-gate-header">
        <span className="checkpoint-label">
          {failed ? 'Checkpoint 5 · Verification' : 'Checkpoints 5–6 · Verification & completion'}
        </span>
        <strong>
          {failed ? 'Verification failed' : 'Verification required'}
        </strong>
        <p className="tagline">
          {failed
            ? 'Did the result pass? Task cannot complete until verify passes or you waive it.'
            : 'Agent stopped after mutation. Run verify before this task can be called done.'}
        </p>
      </div>

      {mutatedPaths && mutatedPaths.length > 0 ? (
        <div className="verify-gate-files">
          <span className="verify-gate-label">Mutated paths:</span>
          <ul>
            {mutatedPaths.slice(0, 8).map((path) => (
              <li key={path}>
                <code>{path}</code>
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      {lastVerifyCommand ? (
        <p className="verify-gate-meta">
          Verify command: <code>{lastVerifyCommand}</code>
        </p>
      ) : null}

      {showOutput && lastVerifyOutput ? (
        <pre className="verify-gate-output">{lastVerifyOutput}</pre>
      ) : null}

      <div className="verify-gate-actions">
        <button type="button" disabled={busy} onClick={() => void onRunVerify(taskId)}>
          Run verify
        </button>
        <button type="button" disabled={busy} onClick={() => void onRetryTask(taskId)}>
          Retry task
        </button>
        {lastVerifyOutput ? (
          <button type="button" disabled={busy} onClick={() => setShowOutput((v) => !v)}>
            {showOutput ? 'Hide failing output' : 'Show failing output'}
          </button>
        ) : null}
        <button
          type="button"
          className="muted"
          disabled={busy}
          onClick={() => void onWaiveVerification(taskId)}
        >
          Waive verification
        </button>
        <button type="button" disabled={busy} onClick={() => void onCancelTask(taskId)}>
          Cancel task
        </button>
      </div>
    </div>
  );
}
