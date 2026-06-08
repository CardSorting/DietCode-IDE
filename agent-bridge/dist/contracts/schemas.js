const PARTIAL_KEYS = [
    'complete',
    'partial',
    'warnings',
    'fallbackUsed',
    'truncated',
    'recoveryHint',
    'nextRecommendedCommand',
];
export function extractPartialMeta(raw) {
    const warnings = Array.isArray(raw.warnings)
        ? raw.warnings.filter((w) => typeof w === 'string')
        : [];
    return {
        complete: raw.complete !== false,
        partial: raw.partial === true,
        warnings,
        fallbackUsed: raw.fallbackUsed === true,
        truncated: raw.truncated === true,
        recoveryHint: typeof raw.recoveryHint === 'string' ? raw.recoveryHint : undefined,
        nextRecommendedCommand: typeof raw.nextRecommendedCommand === 'string' ? raw.nextRecommendedCommand : undefined,
    };
}
export function normalizeBridgeResult(raw, resultKey, includeRaw = false) {
    const meta = extractPartialMeta(raw);
    const result = (resultKey ? raw[resultKey] : raw);
    const envelope = {
        result,
        ...meta,
    };
    if (includeRaw) {
        envelope.raw = raw;
    }
    return envelope;
}
export function normalizeRpcSuccess(envelope, includeRaw = false) {
    const raw = envelope.result ?? {};
    return normalizeBridgeResult(raw, null, includeRaw);
}
export function hasPartialSuccessKeys(raw) {
    return PARTIAL_KEYS.some((key) => key in raw);
}
export function assertMutationReceipt(raw) {
    const required = [
        'path',
        'beforeContentHash',
        'postContentHash',
        'patchFingerprint',
        'readSourceBefore',
        'applyChannel',
        'atomic',
    ];
    for (const key of required) {
        if (!(key in raw)) {
            throw new Error(`mutation receipt missing key: ${key}`);
        }
    }
    if (raw.atomic !== true) {
        throw new Error('mutation receipt atomic must be true');
    }
}
export function assertBatchReceipt(raw) {
    const required = ['atomic', 'appliedCount', 'rolledBack', 'fileReceipts'];
    for (const key of required) {
        if (!(key in raw)) {
            throw new Error(`batch receipt missing key: ${key}`);
        }
    }
}
//# sourceMappingURL=schemas.js.map