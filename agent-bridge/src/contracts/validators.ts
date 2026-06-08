import type { RuntimeCapabilities } from './types.js';

const MUTATION_RECEIPT_KEYS = [
  'path',
  'beforeContentHash',
  'postContentHash',
  'patchFingerprint',
  'readSourceBefore',
  'applyChannel',
  'atomic',
] as const;

const BATCH_RECEIPT_KEYS = ['atomic', 'appliedCount', 'rolledBack', 'fileReceipts'] as const;

const TOOL_CAPABILITIES_KEYS = [
  'mode',
  'contractVersion',
  'agentSafeMethods',
  'deprecatedMethods',
  'deterministicSearchMethods',
  'mutatingMethods',
  'internalNamespaces',
  'semanticSearchDisabled',
  'rankingPolicy',
  'scoringDisabled',
] as const;

const RUNTIME_DIAGNOSTICS_KEYS = [
  'mode',
  'available',
  'mutationAuthority',
  'recordAuthority',
  'complete',
  'partial',
] as const;

export function validateMutationReceipt(receipt: Record<string, unknown>): string[] {
  const errors: string[] = [];
  for (const key of MUTATION_RECEIPT_KEYS) {
    if (!(key in receipt)) {
      errors.push(`mutation receipt missing key: ${key}`);
    }
  }
  if (receipt.atomic !== true) {
    errors.push('mutation receipt atomic must be true');
  }
  return errors;
}

export function validateBatchMutationReceipt(receipt: Record<string, unknown>): string[] {
  const errors: string[] = [];
  for (const key of BATCH_RECEIPT_KEYS) {
    if (!(key in receipt)) {
      errors.push(`batch receipt missing key: ${key}`);
    }
  }
  if (!Array.isArray(receipt.fileReceipts)) {
    errors.push('fileReceipts must be list');
  }
  return errors;
}

export function validateToolCapabilities(result: Record<string, unknown>): string[] {
  const errors: string[] = [];
  for (const key of TOOL_CAPABILITIES_KEYS) {
    if (!(key in result)) {
      errors.push(`tool.capabilities missing key: ${key}`);
    }
  }
  if (result.semanticSearchDisabled !== true) {
    errors.push('semanticSearchDisabled must be true');
  }
  if (result.rankingPolicy !== 'none') {
    errors.push('rankingPolicy must be none');
  }
  return errors;
}

export function validateRuntimeDiagnostics(result: Record<string, unknown>): string[] {
  const errors: string[] = [];
  for (const key of RUNTIME_DIAGNOSTICS_KEYS) {
    if (!(key in result)) {
      errors.push(`runtime.diagnostics missing key: ${key}`);
    }
  }
  return errors;
}

export function assertRuntimeCapabilities(capabilities: RuntimeCapabilities): void {
  const required: Array<keyof RuntimeCapabilities> = [
    'deterministicSearch',
    'patchReceipts',
    'batchReceipts',
    'runtimeTimeline',
    'broccoliqJournal',
    'operationStatus',
    'partialSuccessEnvelopes',
  ];
  const missing = required.filter((key) => !capabilities[key]);
  if (missing.length > 0) {
    throw new Error(`missing runtime capabilities: ${missing.join(', ')}`);
  }
}
