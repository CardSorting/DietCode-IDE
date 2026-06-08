import type { BridgeResult, PartialResultMeta } from './types.js';

const PARTIAL_KEYS = [
  'complete',
  'partial',
  'warnings',
  'fallbackUsed',
  'truncated',
  'recoveryHint',
  'nextRecommendedCommand',
] as const;

export function extractPartialMeta(raw: Record<string, unknown>): PartialResultMeta {
  const warnings = Array.isArray(raw.warnings)
    ? raw.warnings.filter((w): w is string => typeof w === 'string')
    : [];

  return {
    complete: raw.complete !== false,
    partial: raw.partial === true,
    warnings,
    fallbackUsed: raw.fallbackUsed === true,
    truncated: raw.truncated === true,
    recoveryHint: typeof raw.recoveryHint === 'string' ? raw.recoveryHint : undefined,
    nextRecommendedCommand:
      typeof raw.nextRecommendedCommand === 'string' ? raw.nextRecommendedCommand : undefined,
  };
}

export function normalizeBridgeResult<T>(
  raw: Record<string, unknown>,
  resultKey: string | null,
  includeRaw = false,
): BridgeResult<T> {
  const meta = extractPartialMeta(raw);
  const result = (resultKey ? raw[resultKey] : raw) as T;

  const envelope: BridgeResult<T> = {
    result,
    ...meta,
  };

  if (includeRaw) {
    envelope.raw = raw;
  }

  return envelope;
}

export function normalizeRpcSuccess<T>(
  envelope: { result?: Record<string, unknown> },
  includeRaw = false,
): BridgeResult<T> {
  const raw = envelope.result ?? {};
  return normalizeBridgeResult<T>(raw, null, includeRaw);
}

export function hasPartialSuccessKeys(raw: Record<string, unknown>): boolean {
  return PARTIAL_KEYS.some((key) => key in raw);
}

export function assertMutationReceipt(raw: Record<string, unknown>): void {
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

export function assertBatchReceipt(raw: Record<string, unknown>): void {
  const required = ['atomic', 'appliedCount', 'rolledBack', 'fileReceipts'];
  for (const key of required) {
    if (!(key in raw)) {
      throw new Error(`batch receipt missing key: ${key}`);
    }
  }
}
