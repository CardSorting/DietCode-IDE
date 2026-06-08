export { DietCodeBridgeClient } from './client/DietCodeBridgeClient.js';
export { RpcTransport, MockRpcTransport, CLIENT_SCHEMA_VERSION } from './client/RpcTransport.js';
export { buildRuntimeProfile } from './client/RuntimeProfile.js';
export { detectRuntimeCapabilities, assertRequiredCapabilities, listRequiredFeatures, } from './capabilities/detectRuntimeCapabilities.js';
export { bridgeError, mapRpcError, unsupportedCapabilityError } from './contracts/errors.js';
export { normalizeBridgeResult, normalizeRpcSuccess, extractPartialMeta, hasPartialSuccessKeys, } from './contracts/schemas.js';
//# sourceMappingURL=index.js.map