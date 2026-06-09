/** Build minimal single-hunk unified diffs for coherence recovery retries. */

export interface LineReplacement {
  search: string;
  replace: string;
}

export function parseSingleLineReplacement(unifiedDiff: string): LineReplacement | null {
  const removed: string[] = [];
  const added: string[] = [];
  for (const line of unifiedDiff.split('\n')) {
    if (line.startsWith('---') || line.startsWith('+++') || line.startsWith('@@')) {
      continue;
    }
    if (line.startsWith('-')) {
      removed.push(line.slice(1));
    } else if (line.startsWith('+')) {
      added.push(line.slice(1));
    }
  }
  if (removed.length === 1 && added.length === 1) {
    return { search: removed[0], replace: added[0] };
  }
  return null;
}

export function buildLineReplacementPatch(
  relPath: string,
  search: string,
  replace: string,
): string {
  return (
    `--- ${relPath}\n` +
    `+++ ${relPath}\n` +
    `@@ -1,1 +1,1 @@\n` +
    `-${search}\n` +
    `+${replace}\n`
  );
}

export function buildLineReplacementPatchFromContent(
  relPath: string,
  content: string,
  search: string,
  replace: string,
): string {
  const lines = content.split('\n');
  let idx = lines.findIndex((line) => line === search || line.trim() === search.trim());
  if (idx < 0) {
    const assignmentMatch = search.trim().match(/^(\w+)\s*=/);
    if (assignmentMatch) {
      const name = assignmentMatch[1];
      const pattern = new RegExp(`^${name}\\s*=\\s*`);
      idx = lines.findIndex((line) => pattern.test(line.trim()));
    }
  }
  if (idx < 0) {
    throw new Error(`search line not found in ${relPath}`);
  }
  const start = idx + 1;
  const end = idx + 1;
  const oldBlock = lines.slice(idx, idx + 1).map((l) => `-${l}`).join('\n');
  const newLine = replace.startsWith('+') ? replace : `+${replace}`;
  return (
    `--- ${relPath}\n` +
    `+++ ${relPath}\n` +
    `@@ -${start},${end - start + 1} +${start},1 @@\n` +
    `${oldBlock}\n` +
    `${newLine}\n`
  );
}
