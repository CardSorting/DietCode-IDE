export { DietCodeBridgeClient } from './client/DietCodeBridgeClient.js';
export { RpcTransport, CLIENT_SCHEMA_VERSION, DEFAULT_SOCKET_PATH, DEFAULT_TOKEN_PATH, } from './client/RpcTransport.js';
export { BRIDGE_PACKAGE_VERSION, resolveAppPath, resolveTransportConfig, } from './client/config.js';
export { waitForReady, resolveConnectOptions } from './client/connection.js';
export { buildRuntimeProfile } from './client/RuntimeProfile.js';
export { detectRuntimeCapabilities, assertRequiredCapabilities, listRequiredFeatures, } from './capabilities/detectRuntimeCapabilities.js';
export { DietCodeBridgeError, isBridgeError, toBridgeError, resolveBridgeRecovery } from './contracts/BridgeError.js';
export { bridgeError, mapRpcError, unsupportedCapabilityError } from './contracts/errors.js';
export { normalizeBridgeResult, normalizeRpcSuccess, extractPartialMeta, hasPartialSuccessKeys, } from './contracts/schemas.js';
export { validateMutationReceipt, validateBatchMutationReceipt, validateToolCapabilities, validateRuntimeDiagnostics, } from './contracts/validators.js';
export { readFileWithCoherence } from './adapters/fileAdapter.js';
export { parseCoherenceMismatch, refreshCoherenceContext, buildCoherenceStaleRecovery, buildCoherenceOperatorRequired, } from './workflows/coherenceRecovery.js';
export { buildLineReplacementPatch, buildLineReplacementPatchFromContent, parseSingleLineReplacement, } from './utils/unifiedDiff.js';
export { createTaskCoherenceLogger } from './telemetry/coherenceEvents.js';
//# sourceMappingURL=index.js.map