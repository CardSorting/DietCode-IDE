import { fetchWorkspaceRevision } from '../adapters/runtimeAdapter.js';
export async function verifyAfterMutation(transport, revisionBefore, receipt) {
    const revisionAfter = await fetchWorkspaceRevision(transport);
    return {
        revisionBefore,
        revisionAfter,
        revisionBumped: revisionAfter > revisionBefore,
        receipt,
    };
}
//# sourceMappingURL=verifyAfterMutation.js.map