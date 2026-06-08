import type { RpcCaller } from '../client/RpcTransport.js';
import type { RuntimeCapabilities, RuntimeProfile } from '../contracts/types.js';
export declare function detectRuntimeCapabilities(transport: RpcCaller): Promise<RuntimeProfile>;
export declare function assertRequiredCapabilities(capabilities: RuntimeCapabilities): void;
export declare function listRequiredFeatures(): string[];
//# sourceMappingURL=detectRuntimeCapabilities.d.ts.map