import { unsupportedCapabilityError } from '../contracts/errors.js';
import { buildRuntimeProfile } from '../client/RuntimeProfile.js';
import { CLIENT_SCHEMA_VERSION } from '../client/RpcTransport.js';
const REQUIRED_FEATURES = [
    { key: 'deterministicSearch', label: 'deterministic search (search.literal/tokens/paths)' },
    { key: 'patchReceipts', label: 'patch receipts (patch.apply)' },
    { key: 'batchReceipts', label: 'batch receipts (patch.applyBatch)' },
    { key: 'runtimeTimeline', label: 'runtime timeline' },
    { key: 'broccoliqJournal', label: 'BroccoliQ runtime journal (runtime.diagnostics)' },
    { key: 'operationStatus', label: 'operation.status replay' },
    { key: 'partialSuccessEnvelopes', label: 'partial-success envelopes' },
];
export async function detectRuntimeCapabilities(transport) {
    const [capabilitiesEnvelope, diagnosticsEnvelope] = await Promise.all([
        transport.call('tool.capabilities', {}),
        transport.call('runtime.diagnostics', {}),
    ]);
    if (!capabilitiesEnvelope.ok || !capabilitiesEnvelope.result) {
        throw unsupportedCapabilityError('tool.capabilities', capabilitiesEnvelope.error?.message ?? 'call failed');
    }
    if (!diagnosticsEnvelope.ok || !diagnosticsEnvelope.result) {
        throw unsupportedCapabilityError('runtime.diagnostics', diagnosticsEnvelope.error?.message ?? 'call failed');
    }
    const profile = buildRuntimeProfile({
        capabilitiesRaw: capabilitiesEnvelope.result,
        diagnosticsRaw: diagnosticsEnvelope.result,
        schemaVersion: CLIENT_SCHEMA_VERSION,
    });
    assertRequiredCapabilities(profile.capabilities);
    return profile;
}
export function assertRequiredCapabilities(capabilities) {
    const missing = [];
    for (const feature of REQUIRED_FEATURES) {
        if (!capabilities[feature.key]) {
            missing.push(feature.label);
        }
    }
    if (missing.length > 0) {
        const err = unsupportedCapabilityError('required runtime features', missing.join('; '));
        throw err;
    }
}
export function listRequiredFeatures() {
    return REQUIRED_FEATURES.map((f) => f.label);
}
//# sourceMappingURL=detectRuntimeCapabilities.js.map