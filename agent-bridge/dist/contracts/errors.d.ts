import type { BridgeError, BridgeErrorCode, RpcEnvelope } from './types.js';
export declare function bridgeError(code: BridgeErrorCode, message: string, rawError?: Record<string, unknown>, overrides?: Partial<Pick<BridgeError, 'recoveryHint' | 'nextRecommendedCommand' | 'retrySafe'>>): BridgeError;
export declare function mapRpcError(envelope: RpcEnvelope, context?: string): BridgeError;
export declare function unsupportedCapabilityError(feature: string, detail: string): BridgeError;
//# sourceMappingURL=errors.d.ts.map