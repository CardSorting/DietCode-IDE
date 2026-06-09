/** Build minimal single-hunk unified diffs for coherence recovery retries. */
export function buildLineReplacementPatch(relPath, search, replace) {
    return (`--- ${relPath}\n` +
        `+++ ${relPath}\n` +
        `@@ -1,1 +1,1 @@\n` +
        `-${search}\n` +
        `+${replace}\n`);
}
export function buildLineReplacementPatchFromContent(relPath, content, search, replace) {
    const lines = content.split('\n');
    const idx = lines.findIndex((line) => line === search || line.trim() === search.trim());
    if (idx < 0) {
        throw new Error(`search line not found in ${relPath}`);
    }
    const start = idx + 1;
    const end = idx + 1;
    const oldBlock = lines.slice(idx, idx + 1).map((l) => `-${l}`).join('\n');
    const newLine = replace.startsWith('+') ? replace : `+${replace}`;
    return (`--- ${relPath}\n` +
        `+++ ${relPath}\n` +
        `@@ -${start},${end - start + 1} +${start},1 @@\n` +
        `${oldBlock}\n` +
        `${newLine}\n`);
}
//# sourceMappingURL=unifiedDiff.js.map