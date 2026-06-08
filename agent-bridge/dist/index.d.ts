export { DietCodeBridgeClient } from './client/DietCodeBridgeClient.js';
export { RpcTransport, MockRpcTransport, CLIENT_SCHEMA_VERSION } from './client/RpcTransport.js';
export { buildRuntimeProfile } from './client/RuntimeProfile.js';
export { detectRuntimeCapabilities, assertRequiredCapabilities, listRequiredFeatures, } from './capabilities/detectRuntimeCapabilities.js';
export { bridgeError, mapRpcError, unsupportedCapabilityError } from './contracts/errors.js';
export { normalizeBridgeResult, normalizeRpcSuccess, extractPartialMeta, hasPartialSuccessKeys, } from './contracts/schemas.js';
export type { BridgeError, BridgeErrorCode, BridgeEnvelope, BridgeResult, RuntimeProfile, RuntimeCapabilities, SafePatchResult, SafeBatchPatchResult, PatchBatchEntry, SearchOptions, PatchOptions, BatchPatchOptions, TimelineOptions, ActivityOptions, OperationStatusResult, VerifyFastResult, TransportOptions, MutationReceipt, BatchMutationReceipt, StalePatchRecovery, } from './contracts/types.js';
//# sourceMappingURL=index.d.ts.map