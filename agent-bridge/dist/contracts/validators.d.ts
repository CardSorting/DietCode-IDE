import type { RuntimeCapabilities } from './types.js';
export declare function validateMutationReceipt(receipt: Record<string, unknown>): string[];
export declare function validateBatchMutationReceipt(receipt: Record<string, unknown>): string[];
export declare function validateToolCapabilities(result: Record<string, unknown>): string[];
export declare function validateRuntimeDiagnostics(result: Record<string, unknown>): string[];
export declare function assertRuntimeCapabilities(capabilities: RuntimeCapabilities): void;
//# sourceMappingURL=validators.d.ts.map