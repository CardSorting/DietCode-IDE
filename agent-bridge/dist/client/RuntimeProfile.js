export function buildRuntimeProfile(input) {
    const capabilities = input.capabilitiesRaw;
    const diagnostics = input.diagnosticsRaw;
    const agentSafe = asStringArray(capabilities.agentSafeMethods);
    const deterministic = asStringArray(capabilities.deterministicSearchMethods);
    const mutating = asStringArray(capabilities.mutatingMethods);
    const detected = {
        deterministicSearch: hasAll(deterministic, 'search.literal', 'search.tokens', 'search.paths'),
        patchReceipts: mutating.includes('patch.apply'),
        batchReceipts: mutating.includes('patch.applyBatch'),
        runtimeTimeline: agentSafe.includes('runtime.timeline'),
        broccoliqJournal: diagnostics.available === true &&
            typeof diagnostics.mutationAuthority === 'string' &&
            typeof diagnostics.recordAuthority === 'string',
        operationStatus: agentSafe.includes('operation.status'),
        partialSuccessEnvelopes: 'complete' in diagnostics ||
            'partial' in diagnostics ||
            capabilities.semanticSearchDisabled === true,
    };
    return {
        connected: true,
        contractVersion: String(capabilities.contractVersion ?? 'unknown'),
        schemaVersion: input.schemaVersion,
        capabilities: detected,
        agentSafeMethodCount: agentSafe.length,
        semanticSearchDisabled: capabilities.semanticSearchDisabled === true,
        rankingPolicy: String(capabilities.rankingPolicy ?? 'none'),
        diagnosticsAvailable: diagnostics.available === true,
        workspacePath: typeof diagnostics.workspacePath === 'string' ? diagnostics.workspacePath : undefined,
        mutationAuthority: typeof diagnostics.mutationAuthority === 'string'
            ? diagnostics.mutationAuthority
            : undefined,
        recordAuthority: typeof diagnostics.recordAuthority === 'string' ? diagnostics.recordAuthority : undefined,
    };
}
function asStringArray(value) {
    return Array.isArray(value) ? value.filter((v) => typeof v === 'string') : [];
}
function hasAll(list, ...items) {
    return items.every((item) => list.includes(item));
}
//# sourceMappingURL=RuntimeProfile.js.map