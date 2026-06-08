import { useEffect, useState } from 'react';
import type { SessionState } from '../hooks/useKernel';

interface Props {
  sessionDiffs?: SessionState['recentDiffs'];
}

export function DiffPanel({ sessionDiffs }: Props) {
  const [diff, setDiff] = useState('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;

    const fromSession = (diffs: SessionState['recentDiffs']) => {
      if (!diffs?.length) return '';
      return diffs
        .map((entry) => {
          const header = `# ${entry.path}${entry.taskId ? ` (${entry.taskId})` : ''}`;
          return entry.preview ? `${header}\n${entry.preview}` : header;
        })
        .join('\n---\n');
    };

    const load = async () => {
      setLoading(true);
      try {
        const sessionPreview = fromSession(sessionDiffs);
        if (sessionPreview && !cancelled) {
          setDiff(sessionPreview);
        }

        const res = await fetch('/api/session');
        if (res.ok) {
          const data = (await res.json()) as { recentDiffs?: SessionState['recentDiffs'] };
          const preview = fromSession(data.recentDiffs);
          if (!cancelled && preview) {
            setDiff(preview);
            setLoading(false);
            return;
          }
        }

        const rpcRes = await fetch('/api/rpc', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            method: 'runtime.operation.recent',
            params: { limit: 5, compact: true },
          }),
        });
        const rpcData = (await rpcRes.json()) as {
          result?: { operations?: Array<{ summary?: string; diffPreview?: string }> };
        };
        if (cancelled) return;
        const ops = rpcData.result?.operations ?? [];
        const preview = ops
          .map((op) => op.diffPreview ?? op.summary ?? '')
          .filter(Boolean)
          .join('\n---\n');
        setDiff(
          preview ||
            sessionPreview ||
            'No recent diffs. Mutations appear here ephemerally after patch.apply.',
        );
      } catch {
        if (!cancelled) {
          const fallback = fromSession(sessionDiffs);
          setDiff(fallback || 'Unable to load diffs. Is dietcode-kernel running?');
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    void load();
    const timer = setInterval(load, 15000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [sessionDiffs]);

  return (
    <div>
      {loading && !diff ? <p className="empty">Loading diffs…</p> : null}
      <pre className="diff-block">{diff}</pre>
    </div>
  );
}
