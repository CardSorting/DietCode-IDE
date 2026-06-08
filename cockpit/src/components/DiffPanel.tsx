import { useEffect, useState } from 'react';

export function DiffPanel() {
  const [diff, setDiff] = useState<string>('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      setLoading(true);
      try {
        const res = await fetch('/api/rpc', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            method: 'runtime.operation.recent',
            params: { limit: 5, compact: true },
          }),
        });
        const data = (await res.json()) as {
          result?: { operations?: Array<{ summary?: string; diffPreview?: string }> };
        };
        if (cancelled) return;
        const ops = data.result?.operations ?? [];
        const preview = ops
          .map((op) => op.diffPreview ?? op.summary ?? '')
          .filter(Boolean)
          .join('\n---\n');
        setDiff(preview || 'No recent diffs. Mutations will appear here after patch.apply.');
      } catch {
        if (!cancelled) setDiff('Unable to load diffs. Is dietcode-kernel running?');
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
  }, []);

  return (
    <div>
      {loading && !diff ? <p className="empty">Loading diffs…</p> : null}
      <pre className="diff-block">{diff}</pre>
    </div>
  );
}
