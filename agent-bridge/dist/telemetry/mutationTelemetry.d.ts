export interface MutationPatchAppliedEvent {
    workspace: string;
    path: string;
    beforeHash: string;
    afterHash: string;
    tool: string;
    protocol: string;
    idempotencyKey?: string;
}
export declare function recordMutationPatchApplied(event: MutationPatchAppliedEvent): void;
//# sourceMappingURL=mutationTelemetry.d.ts.map