import { CLIENT_SCHEMA_VERSION } from '../client/config.js';
import { buildRuntimeProfile } from '../client/RuntimeProfile.js';
import type { RpcCaller } from '../client/RpcTransport.js';
import { unsupportedCapabilityError } from '../contracts/errors.js';
import {
  validateRuntimeDiagnostics,
  validateToolCapabilities,
} from '../contracts/validators.js';
import type { RuntimeCapabilities, RuntimeProfile } from '../contracts/types.js';

const REQUIRED_FEATURES: Array<{ key: keyof RuntimeCapabilities; label: string }> = [
  { key: 'deterministicSearch', label: 'deterministic search (search.literal/tokens/paths)' },
  { key: 'patchReceipts', label: 'patch receipts (patch.apply)' },
  { key: 'batchReceipts', label: 'batch receipts (patch.applyBatch)' },
  { key: 'runtimeTimeline', label: 'runtime timeline' },
  { key: 'broccoliqJournal', label: 'BroccoliQ runtime journal (runtime.diagnostics)' },
  { key: 'operationStatus', label: 'operation.status replay' },
  { key: 'partialSuccessEnvelopes', label: 'partial-success envelopes' },
];

export async function detectRuntimeCapabilities(
  transport: RpcCaller,
): Promise<RuntimeProfile> {
  const [capabilitiesEnvelope, diagnosticsEnvelope] = await Promise.all([
    transport.call('tool.capabilities', {}),
    transport.call('runtime.diagnostics', {}),
  ]);

  if (!capabilitiesEnvelope.ok || !capabilitiesEnvelope.result) {
    throw unsupportedCapabilityError(
      'tool.capabilities',
      capabilitiesEnvelope.error?.message ?? 'call failed',
    );
  }

  if (!diagnosticsEnvelope.ok || !diagnosticsEnvelope.result) {
    throw unsupportedCapabilityError(
      'runtime.diagnostics',
      diagnosticsEnvelope.error?.message ?? 'call failed',
    );
  }

  const capabilityErrors = validateToolCapabilities(capabilitiesEnvelope.result);
  if (capabilityErrors.length > 0) {
    throw unsupportedCapabilityError('tool.capabilities contract', capabilityErrors.join('; '));
  }

  const diagnosticsErrors = validateRuntimeDiagnostics(diagnosticsEnvelope.result);
  if (diagnosticsErrors.length > 0) {
    throw unsupportedCapabilityError('runtime.diagnostics contract', diagnosticsErrors.join('; '));
  }

  const profile = buildRuntimeProfile({
    capabilitiesRaw: capabilitiesEnvelope.result,
    diagnosticsRaw: diagnosticsEnvelope.result,
    schemaVersion: CLIENT_SCHEMA_VERSION,
  });

  assertRequiredCapabilities(profile.capabilities);
  return profile;
}

export function assertRequiredCapabilities(capabilities: RuntimeCapabilities): void {
  const missing: string[] = [];
  for (const feature of REQUIRED_FEATURES) {
    if (!capabilities[feature.key]) {
      missing.push(feature.label);
    }
  }
  if (missing.length > 0) {
    throw unsupportedCapabilityError('required runtime features', missing.join('; '));
  }
}

export function listRequiredFeatures(): string[] {
  return REQUIRED_FEATURES.map((f) => f.label);
}
