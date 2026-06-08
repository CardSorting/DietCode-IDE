import type { HealthBanner } from '../hooks/useKernel';

interface Props {
  banners: HealthBanner[];
  activeTaskId?: string | null;
  onReconnect: () => void;
  onRetryTask?: (taskId: string) => void;
  onCancelTask?: (taskId: string) => void;
  onClearSession: () => void;
  onExportSnapshot: () => void;
  onRefreshApprovals: () => void;
  busy?: boolean;
}

export function StatusBanners({
  banners,
  activeTaskId,
  onReconnect,
  onRetryTask,
  onCancelTask,
  onClearSession,
  onExportSnapshot,
  onRefreshApprovals,
  busy,
}: Props) {
  const disconnectedBanner = banners.find((b) => b.id.startsWith('task_disconnected'));
  const disconnectedTaskId = disconnectedBanner?.id.replace('task_disconnected_', '');

  if (banners.length === 0) return null;

  return (
    <div className="status-banners">
      {banners.map((banner) => (
        <div key={banner.id} className={`status-banner severity-${banner.severity}`}>
          <div className="status-banner-text">
            <strong>{banner.message}</strong>
            {banner.detail ? <span className="status-banner-detail">{banner.detail}</span> : null}
          </div>
        </div>
      ))}
      <div className="status-banner-actions">
        <button type="button" disabled={busy} onClick={() => void onReconnect()}>
          Reconnect
        </button>
        {disconnectedTaskId && onRetryTask ? (
          <button
            type="button"
            disabled={busy}
            onClick={() => void onRetryTask(disconnectedTaskId)}
          >
            Retry task
          </button>
        ) : null}
        {activeTaskId && onCancelTask ? (
          <button type="button" disabled={busy} onClick={() => void onCancelTask(activeTaskId)}>
            Cancel task
          </button>
        ) : null}
        <button type="button" disabled={busy} onClick={() => void onRefreshApprovals()}>
          Refresh approvals
        </button>
        <button type="button" disabled={busy} onClick={() => void onExportSnapshot()}>
          Export snapshot
        </button>
        <button type="button" className="muted" disabled={busy} onClick={() => void onClearSession()}>
          Clear session
        </button>
      </div>
    </div>
  );
}
