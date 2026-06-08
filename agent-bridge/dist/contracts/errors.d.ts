import { DietCodeBridgeError } from './BridgeError.js';
import type { BridgeErrorCode, RpcEnvelope } from './types.js';
export declare function bridgeError(code: BridgeErrorCode, message: string, rawError?: Record<string, unknown>, overrides?: Partial<{
    recoveryHint: string;
    nextRecommendedCommand: string;
    retrySafe: boolean;
}>): DietCodeBridgeError;
export declare function mapRpcError(envelope: RpcEnvelope, context?: string): DietCodeBridgeError;
export declare function unsupportedCapabilityError(feature: string, detail: string): DietCodeBridgeError;
//# sourceMappingURL=errors.d.ts.map